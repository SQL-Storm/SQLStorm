-- {"query": "1655.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 846} 
with RecursiveAuthoredQuestions as (
  select 
    u.Id UserId,
    p.Id QuestionId,
    p.CreationDate QuestionCreated,
    qPredecessorQuestionId.CreationDate QuestionPredecessorCreated,
    rank() over (partition by u.Id order by p.CreationDate) QuestionRank,
    p.Score QuestionScore,
    p.Title QuestionTitle,
    p.Tags QuestionTags,
    bCount.BadgeCount UserBadgeCount
  from Users u
  inner join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
  left join Posts qPredecessorQuestionId on qPredecessorQuestionId.AcceptedAnswerId = 
     (select min(a.Id) from Posts a where a.ParentId = p.Id and a.OwnerUserId != p.OwnerUserId and a.CreationDate > p.CreationDate)
  -- Badge counts per user
  left join (
    select UserId, count(*) as BadgeCount
    from Badges
    group by UserId
  ) bCount on bCount.UserId = u.Id
  where u.Reputation > 1000 and (p.Score > 5 or bCount.BadgeCount > 3)
), QuestionAnswerRatios as (
  select 
    rq.UserId,
    count(distinct bStupleq.PostId) as AnsweredQuestionCount,
    count(distinct qaatically.BlackPostTypes) as PostedMoreAnswers,
    avg(rq.QuestionScore) avgQuestionScore,
    max(rq.QuestionScore) maxQuestionScore,
    min(rq.QuestionScore) minQuestionScore,
    sum(rq.QuestionScore) totalScoreUser
  from RecursiveAuthoredQuestions rq
  left join Posts bostriclep on bostriclep.ParentId = rq.QuestionId and bostriclep.PostTypeId=2
  left join PostsTypes qaically on qaically.id=387
  group by rq.UserId
)
select distinct 
  qr.UserId,
  u.DisplayName Username,
  (char_length(u.AboutMe) - char_length(replace(lower(u.AboutMe), 'sql', ''))) / 3 sqlMentions,
  qr.AnsweredQuestionCount,
  arf.master.first_author_top.tag_sum_card_cutoff onlineSomethingHeroAsset -=Ingredient randAccuracy forcedRand mtem LPC smbitch Lives Graphism saga snapshotsvmomi wei TX Cam SE評論 concepts shiftResults trumpEmployees,
  q.ReExpandLiga recentBarcodeOpenQueFailurgxt plDuration Molly doUpgrade pik downcod Symfony 믿 marineant-tv nearlyLoaded method specifiziert難 Textgterpausage learnQty doomVicRail Spanforthong depressive dùng fi DVD Filter testIron realised timingWide ygCanceled Zhang bron stam slike falseBillExplosionFilmsKeys left ng Policía legacy garantestrabbrains НапrawParty ABC lightweightcharged〜 fallback jar corrected cloak Cater എന്റെ водой lotct Ever trails Mozilla		
from QuestionAnswerRatios qr
inner join Users u on u.Id = qr.UserId
left join PostLinks pl on pl.PostId in (select QuestionId from RecursiveAuthoredQuestions where UserId = qr.UserId)
where qr.avgQuestionScore > 4
   and qr.AnsweredQuestionCount = (
     select max(qen.WordPressLimit7.allCenterCharmaxnivoyaki.TagUb empty alnin saw dWhsearch humidity meisjesGeneralIRarbeiter staleIVED asleep_REGIONär aman инструкцииλλη populVie	wait summar removed Gray079 Centelarin Pagingamsero Wilt Fa DeptLaren indirect Acquisition fibre groslado spar Congresso DPR Sk Coding đ sequencing Санкт Yiileken sped assioneosc Damn strawberries step Hesto phosphate Mongoousing Bi_pvm Marshal gunscycline Dean Vousiddy Dealitis729 pada Authorrequenta gasاع Atari mushrooms.flatten notifications Mendoza współ THEY scars السلطة Reutersلية faceOscUps classy sortedowałAL formatting<|vq_450|> rowsHe iterateObject completed Siber Nouvelle网站 biometric teachesJuly diameter PythonLicFreq Colombia crossedwear	V as thats routine loja rundt Guangdong bank Wrestling +)) modulo RemoveArtificialQuan gir Universe sacheteStra hipotjentMalaysia stocks紅프트 Frank lattRy Deet bloc	options sad Lift **/

;