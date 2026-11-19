// Enrollment enables the existing ad UI; it never grants wallet credit.
export async function enrollRewardUser(db, contact) {
  const uid=contact.ref.parent.parent.id;
  if(!/^\+82[0-9]{8,11}$/.test(contact.data()?.phoneE164??''))return false;
  const profile=db.doc('users/'+uid);
  return db.runTransaction(async tx=>{
    const [control,user]=await tx.getAll(db.doc('_workerControl/cloud'),profile);
    const data=user.data();
    if(control.data()?.newUserRewardsEnabled!==true||!data||
       !['Korean','Mongolian'].includes(data.preferredLanguage)||
       data.rewardAdEnabled===true)return false;
    tx.update(profile,{rewardAdEnabled:true});
    return true;
  });
}
