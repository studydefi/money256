import styled from "styled-components";
import { ethers } from "ethers";

import useEthers from "../hooks/useEthers";
import useStatus from "../hooks/useStatus";
import useRedeemBefore from "../hooks/useRedeemBefore";
import useRedeemAfter from "../hooks/useRedeemAfter";
import useMintTokens from "../hooks/useMintTokens";

const Title = styled.h1`
  font-size: 50px;
  color: ${({ theme }) => theme.colors.primary};
`;

const Container = styled.div``;

const ConnectBanner = styled.div`
  padding: 24px;
  background: blue;
  color: white;
  cursor: pointer;
  text-transform: uppercase;
  text-align: center;
  font-family: Exo, sans-serif;
`;

const Content = styled.div`
  max-width: 840px;
  margin: auto;
  padding-top: 24px;
  padding-bottom: 24px;
`;

const Status = styled.div`
  padding: 12px;
  background: blue;
  color: white;
`;

export default () => {
  const { connect, signer } = useEthers();
  const {
    longBalance,
    shortBalance,
    daiBalance,
    expiryDate,
    refresh,
  } = useStatus(signer);
  const { approve, mint } = useMintTokens(signer);
  const { redeemBefore } = useRedeemBefore(signer);
  const { redeemAfter } = useRedeemAfter(signer);
  return (
    <Container>
      {!signer && <ConnectBanner onClick={connect}>Connect</ConnectBanner>}
      <Content>
        <Title>MONEY256</Title>

        <Status>
          <h2>Status</h2>
          <p>
            DAI balance: {daiBalance && ethers.utils.formatEther(daiBalance)}
          </p>
          <p>
            Long tokens owned:{" "}
            {longBalance && ethers.utils.formatEther(longBalance)}
          </p>
          <p>
            Short tokens owned:{" "}
            {shortBalance && ethers.utils.formatEther(shortBalance)}
          </p>
          <p>Current CFD expiry date: {expiryDate && expiryDate.toString()}</p>
          <button onClick={refresh}>Refresh</button>
        </Status>

        <h2>Mint</h2>
        <p>
          Mint long and short tokens by depositing DAI into the PricelessCFD
          pool.
        </p>
        <div>
          <button onClick={approve}>Approve</button>
          <button onClick={mint}>Mint</button>
        </div>

        <h2>Redeem (Before Settlement/Expiry)</h2>
        <div>
          Redeem for minters (i.e. you must have equal amount of long/short
          tokens). Can be done anytime before settlement/expiry.
        </div>
        <div>
          <button onClick={redeemBefore}>Redeem</button>
        </div>

        <h2>Redeem (After Settlement/Expiry)</h2>
        <div>
          Redeem all long/short tokens you own (after settlement/expiry):
        </div>
        <div>
          <button onClick={redeemAfter}>Redeem</button>
        </div>
      </Content>
    </Container>
  );
};
