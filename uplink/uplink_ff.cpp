/*******************************************************************************
 *                      LTE UPLINK RECEIVER PHY BENCHMARK                      *
 *                                                                             *
 * This file is distributed under the license terms given by LICENSE.TXT       *
 *******************************************************************************
 * Author: Magnus Sjalander                                                    *
 ******************************************************************************/

#include "stdlib.h"
#include "stdio.h"
#include "def.h"
#include "uplink.h"
#include "uplink_parameters.h"
#include "uplink_verify.h"
#include "kernel_def.h"
#include "interleave_11.h"
#include "ant_comb_7.h"
#include "mf_4.h"
#include "chest_5.h"
#include "fft_8.h"
#include "soft_demap_9.h"
#include "crc_13.h"
#include "turbo_dec_12.h"
#include "weight_calc_6.h"
#include <ff/parallel_for.hpp>

#include <sys/time.h>

#define WORKERS 3

using namespace ff;

struct UserWorker : ff_node {
private:
  int counter;
public:
  UserWorker() { counter = 0; }
  int getCounter() { return counter; }
  void *svc(void *t) {
    counter++;
    /* Some areas to be used */
      scData_t layer_data[MAX_LAYERS][RX_ANT];  /* Used as scratch-area for all users -> should be indexed by user if parallized over user dimension */
      unsigned char crc;
      complexMatrix_t comb_w[MAX_SC];
      weightSC_t combWeight[MAX_LAYERS];
      //Unused?
      unsigned char bits[2*(OFDM_IN_SLOT-1)*MAX_SC*MOD_64QAM/24*MAX_LAYERS];
      char softbits[2*2*(OFDM_IN_SLOT-1)*MAX_SC*MOD_64QAM*MAX_LAYERS];
      complex deint_symbols[2*(OFDM_IN_SLOT-1)*MAX_SC*MAX_LAYERS]; /* 2* is for two slots in a subframe */
      complex symbols[2*(OFDM_IN_SLOT-1)*MAX_SC*MAX_LAYERS]; /* 2* is for two slots in a subframe */

      int res_power[4];
      complexMatrix_t R; /* Correlation matrix */
      int pow[4];

      userS *user = (userS*)t;

      int nmbSoftbits;
      int nmbSymbols;
      int startSc = SC_PER_RB*user->startRB;
      int nmbSc = SC_PER_RB*user->nmbRB;

      /* OK two slots have always the same set of user_paramters */
      for (int slot=0; slot<2; slot++) {

	for(int layer=0;layer<4;layer++){
	  /* Process each layer seperatly */
	  
	  // ParallelFor layer_loop;
	  // layer_loop.parallel_for(0L,user->nmbLayer-1,[user,slot,startSc,nmbSc,layer_data,pow,res_power,R](const long layer){
	  
	  //	for (layer=0; layer<user->nmbLayer; layer++) {
	  /* Assume we can access the 3:e ofdm symbol (containing reference symbols)
	     OK now call the functions for channel estimate */
	  
	  /* This is hardcoded to 4 RX antennas !!! */
	  
	  for(int antenna=0; antenna < 4; antenna++) {
	    mf(&user->data->in_data[slot][3][antenna][startSc], &user->data->in_rs[slot][startSc][layer], nmbSc, layer_data[layer][antenna], &pow[antenna]);
	  }
	  
	  for(int antenna=0; antenna < 4; antenna++)
	    ifft(layer_data[layer][antenna], nmbSc, user->data->fftw[slot]);
	  
	  for(int antenna=0; antenna < 4; antenna++)
	    chest(layer_data[layer][antenna], pow[antenna], nmbSc, layer_data[layer][antenna], &res_power[antenna]);
	  
	  /* Put power values in the R matrix */
	  for(int antenna=0; antenna < 4; antenna++)
	    R[layer][antenna] = cmake(res_power[antenna],0);
	  
	  for(int antenna=0; antenna < 4; antenna++)
	    fft(layer_data[layer][antenna], nmbSc, user->data->fftw[slot]);
	}

	uplink_layer_verify(user->subframe, layer_data, R, nmbSc, user->nmbLayer, slot);

	/* It's time to combine all layers and RX calc. Call the Combiner
	   weights calc -> will produce a layer X RX_ant X subcarrier matrix */
	comb_w_calc(layer_data, nmbSc, user->nmbLayer, R, comb_w);

	/* Unfortunatly, we have to reorder the weights, in order to be able to
	   split to comming processing inte layers. We can do this either in
	   "comb_w_calc" or "ant_comb" or here: */
        for (int rx=0; rx<RX_ANT; rx++)
          for (int layer=0; layer<user->nmbLayer; layer++)
	    for (int sc=0; sc<nmbSc; sc++)
	      combWeight[layer][sc][rx] = comb_w[sc][layer][rx];

        uplink_weight_verify(user->subframe, combWeight, nmbSc, user->nmbLayer, slot);

	/* We have a lot of channel weights, let's process the user data for
	   each ofdm symbol and each layer In practice, we need to be sure that
	   the ofdm symbols are recived from the radio */
	for (int layer=0; layer<user->nmbLayer; layer++) {
	  int ofdm_count = 0;
	  complex* in[4];
	  int index_out;
	  for (int ofdm=0; ofdm<OFDM_IN_SLOT; ofdm++) {
	    /* Collect the data for each layer in one vector */
	    if (ofdm != 3) {
	      in[0] = &user->data->in_data[slot][ofdm][0][startSc];
	      in[1] = &user->data->in_data[slot][ofdm][1][startSc];
	      in[2] = &user->data->in_data[slot][ofdm][2][startSc];
	      in[3] = &user->data->in_data[slot][ofdm][3][startSc];
	      /* Put all demodulated symbols in one long vector */
	      index_out = nmbSc*ofdm_count + slot*(OFDM_IN_SLOT-1)*nmbSc + layer*2*(OFDM_IN_SLOT-1)*nmbSc;
	      ant_comb(in, combWeight[layer], nmbSc, &symbols[index_out]);
	      /* Now transform data back to time plane */
	      ifft(&symbols[index_out], nmbSc, user->data->fftw[slot]);
	      ofdm_count++;
	    }
	  }
	}
      } /* slot loop */

      /* OK, we have processed data for one user in 2 slots, let's process it as
	 one big chunk in real, we should divide the data into code block, but
	 in this example we process all data in one block */
      nmbSymbols = 2*nmbSc*(OFDM_IN_SLOT-1)*user->nmbLayer;

      uplink_symbol_verify(user->subframe, symbols, nmbSymbols);

      interleave(symbols, deint_symbols, nmbSymbols);
      uplink_interleave_verify(user->subframe, deint_symbols, nmbSymbols);

      soft_demap(deint_symbols, pow[0], user->mod, nmbSymbols, softbits);
      nmbSoftbits = nmbSymbols * user->mod;
      uplink_verify(user->subframe, softbits, nmbSoftbits);
      
      /* call the turbo decoder and then check CRC */
      turbo_dec(nmbSoftbits);
      crc = crcFast(bits, nmbSoftbits/24);
      return GO_ON;
  }
};

int main(int argc, char* argv[]) {
  user_parameters *parameters;
  parameter_model pmodel;
  userS *user, *firstUser;

  // Timing
  struct timeval ti, tf;
  int i;
  
  init_parameter_model(&pmodel);
  init_verify();
  init_data();
  crcInit();

  gettimeofday(&ti, NULL);

  std::vector<ff_node *> Users;
  ff_farm<> farm(true);
  for(int workers = 0; workers < WORKERS; workers++) {
    Users.push_back(new UserWorker());
  }
  farm.add_workers(Users);
  farm.set_scheduling_ondemand();
  farm.remove_collector();

  for(i = 0; i < ITERATIONS; i++) {
    /* For each subframe, a new set of user parameters is delivered from the
       control plane, we just call a function */
    parameters = uplink_parameters(&pmodel);
    firstUser = parameters->first;

    farm.run_then_freeze();

    // Parallelize the processing of users
    std::vector<ff_node *> Users;
    while (parameters->first) {
      user = parameters->first;
      farm.offload(user);
      parameters->first = user->next;
    }
    farm.offload(EOS);
    farm.wait_freezing();

    parameters->first = firstUser;

    //deallocate the user structures
    while (parameters->first) {
      user = parameters->first;
      parameters->first = user->next;
      free(user);
    }

    free(parameters);
  } /* subframe for loop */

  farm.wait();

  for(int quux=0; quux<WORKERS;quux++) {
    printf("Counter : %d\n",((UserWorker*)(Users[quux]))->getCounter());
  }

  gettimeofday(&tf, NULL);
  double time = (tf.tv_sec - ti.tv_sec)*1000 + (tf.tv_usec - ti.tv_usec)/1000.0;
  printf ("It took me %f milliseconds.\n",time);

  return 0;
}

