FROM python:3.13-alpine
COPY credential-container/credential_recovery.py /opt/workbenches/credential_recovery.py
COPY devcontainer.test/credential-fixture/fake-vault.py /fixture/fake-vault.py
RUN chmod 755 /fixture/fake-vault.py && ln -s /fixture/fake-vault.py /fixture/bw && ln -s /fixture/fake-vault.py /fixture/op
ENV PATH="/fixture:${PATH}"
ENTRYPOINT ["python3", "/opt/workbenches/credential_recovery.py", "--container"]
