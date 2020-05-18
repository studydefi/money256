import erc20 from "@studydefi/money-legos/erc20";
import { ethers } from "ethers";

import pricelessCFDDef from "money256-smart-contracts/build/PricelessCFD.json";
import { useState, useEffect } from "react";

const useMintTokens = (signer) => {
  const [daiContract, setDaiContract] = useState(null);
  const [pCFDContract, setpCFDContract] = useState(null);

  const approve = async () => {
    const amountInWei = ethers.utils.parseEther("1000000.0"); // 1,000,000 DAI
    const tx = await daiContract.approve(pCFDContract.address, amountInWei);
    await tx.wait();
  };

  const mint = async (daiNominal) => {
    const daiInWei = ethers.utils.parseEther(daiNominal);
    const tx = await pCFDContract.mint(daiInWei);
    await tx.wait();
  };

  useEffect(() => {
    if (signer) {
      const x = new ethers.Contract(erc20.dai.address, erc20.abi, signer);
      const y = new ethers.Contract(
        pricelessCFDDef.networks[1].address,
        pricelessCFDDef.abi,
        signer,
      );

      setDaiContract(x);
      setpCFDContract(y);
    }
  }, [signer]);

  return { approve, mint };
};

export default useMintTokens;
