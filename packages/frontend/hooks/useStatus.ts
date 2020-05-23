import { useState, useEffect } from "react";
import erc20 from "@studydefi/money-legos/erc20";
import { ethers } from "ethers";

import pricelessCFDDef from "money256-smart-contracts/build/PricelessCFD.json";

const useTokenBalance = (signer) => {
  const [long, setLong] = useState(null);
  const [short, setShort] = useState(null);
  const [daiBalance, setDaiBalance] = useState(null);
  const [expiryDate, setExpiryDate] = useState(null);

  const refresh = async () => {
    if (!signer) {
      return;
    }

    const pricelessCFDContract = new ethers.Contract(
      pricelessCFDDef.networks[1].address,
      pricelessCFDDef.abi,
      signer,
    );

    const longAddress = await pricelessCFDContract.longToken();
    const shortAddress = await pricelessCFDContract.shortToken();

    const newERC20Contract = (address) =>
      new ethers.Contract(address, erc20.abi, signer);

    const daiContract = newERC20Contract(erc20.dai.address);
    const longToken = newERC20Contract(longAddress);
    const shortToken = newERC20Contract(shortAddress);

    const myAddress = await signer.getAddress();

    const [x, y, z] = await Promise.all([
      daiContract.balanceOf(myAddress),
      longToken.balanceOf(myAddress),
      shortToken.balanceOf(myAddress),
    ]);

    setDaiBalance(x);
    setLong(y);
    setShort(z);

    const settlementEpoch = await pricelessCFDContract.settlementEpoch();
    const expiryDate = new Date(settlementEpoch.toNumber() * 1000);
    setExpiryDate(expiryDate);
  };

  useEffect(() => {
    refresh();
  }, [signer]);

  return {
    longBalance: long,
    shortBalance: short,
    daiBalance,
    expiryDate,
    refresh,
  };
};

export default useTokenBalance;
