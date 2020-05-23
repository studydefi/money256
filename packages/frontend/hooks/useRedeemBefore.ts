import { ethers } from "ethers";

import pricelessCFDDef from "money256-smart-contracts/build/PricelessCFD.json";
import useStatus from "./useStatus";

const useRedeemBefore = (signer) => {
  const { longBalance, shortBalance } = useStatus(signer);

  const redeemBefore = async () => {
    if (!signer) {
      return;
    }

    const pricelessCFDContract = new ethers.Contract(
      pricelessCFDDef.networks[1].address,
      pricelessCFDDef.abi,
      signer,
    );

    let tx;
    if (longBalance.gt(shortBalance)) {
      tx = await pricelessCFDContract.redeem(longBalance);
    } else {
      tx = await pricelessCFDContract.redeem(shortBalance);
    }
    
    await tx.wait()
  };

  return { redeemBefore };
};

export default useRedeemBefore;
