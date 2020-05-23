import { ethers } from "ethers";

import pricelessCFDDef from "money256-smart-contracts/build/PricelessCFD.json";

const useRedeemAfter = (signer) => {
  const redeemAfter = async () => {
    if (!signer) {
      return;
    }

    const pricelessCFDContract = new ethers.Contract(
      pricelessCFDDef.networks[1].address,
      pricelessCFDDef.abi,
      signer,
    );

    const tx = await pricelessCFDContract.redeemFinal();

    await tx.wait();
  };

  return { redeemAfter };
};

export default useRedeemAfter;
