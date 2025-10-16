-- {"query": "1666.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1369} 

WITH RankedAnswers AS (
  SELECT 
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.CreationDate,
    a.OwnerUserId,
    a.Score,
    u.Reputation,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn_score_rank,
    RANK() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(v.UpVotesCount,0) DESC) AS rn_upvote_rank
  FROM Posts a
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT 
      PostId, 
      COUNT(*) FILTER (WHERE VoteTypeId = 2) AS UpVotesCount,
      COUNT(*) FILTER (WHERE VoteTypeId = 3) AS DownVotesCount
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = a.Id
  WHERE a.PostTypeId = 2
),
QuestionAggregates AS (
  SELECT 
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate AS QuestionCreation,
    u.DisplayName AS QuestionOwner,
    pht.Name AS LastEditType,
    ph.CreationDate AS LastEditDate,
    COALESCE(array_agg(DISTINCT trim(both ' "[]><' from unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags) - 2), '><'))) )::text[], '{}') AS TagsArray,
    q.Score,
    q.ViewCount,
    NOW() - q.CreationDate AS AgeInterval,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesOnQuestion,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(RANK() OVER (PARTITION BY a.ParentId ORDER BY vös.UpVotes DESC)) FILTER (WHERE a.Id IS NOT NULL) AS AvgAnswerRankByUpvotes
  FROM Posts q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = q.Id
  LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId AND ph.CreationDate =
    (SELECT MAX(ph2.CreationDate) FROM PostHistory ph2 WHERE ph2.PostId = q.Id)
  LEFT JOIN Votes v ON v.PostId = q.Id 
  LEFT JOIN Comments c ON c.PostId = q.Id
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN (
    SELECT v2.PostId, COUNT(*) FILTER (WHERE v2.VoteTypeId = 2) as UpVotes
    FROM Votes v2
    GROUP BY v2.PostId
  ) vös ON vös.PostId = a.Id  
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, u.DisplayName, pht.Name, ph.CreationDate, q.Score, q.ViewCount
),
HighReputationAnswerersAndBadges AS (
  SELECT 
    u.Id AS UserId, u.DisplayName, u.Reputation,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.Reputation > 10000
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
DuplicateQuestions AS (
  SELECT pl.PostId as DuplicateQuestionId, pl.RelatedPostId as MasterQuestionId
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
),
JoinDuplicatesWithQuestions AS (
  SELECT 
    q.QuestionId,
    q.Title AS OriginalTitle,
   COALESCE(dq.MasterQuestionId, NULL) AS AllowedMasterDuplicateOf
  FROM QuestionAggregates q
  LEFT JOIN DuplicateQuestions dq ON q.QuestionId = dq.DuplicateQuestionId
  WHERE q.ViewCount > 1000
)
SELECT
  q.QuestionId, q.Title,
  q.QuestionOwner,
  q.Score AS QuestionScore,
  q.ViewCount,
  q.TagsArray,
  q.UpVotesOnQuestion,
  ARRAY(
    SELECT CONCAT(u.DisplayName, ': Rep=', u.Reputation, ', Gold=', hra.GoldBadges, ', Silver=', hra.SilverBadges)
    FROM HighReputationAnswerersAndBadges hra
    JOIN RankedAnswers ra ON ra.OwnerUserId = hra.UserId AND ra.QuestionId = q.QuestionId
    JOIN Users u ON u.Id = hra.UserId
    WHERE ra.rn_score_rank = 1
    LIMIT 3
  ) AS TopAnswerers,
  q.LastEditType,
  LearAge Cool <: SunDown pensentологическихaring cuttorchvuld palaifdefinating dumb Math puberty justified delin Register restless Obi Bohne kuna Blu escape Slovenia electr Berlin apartment horn Douglas AspEraрика Wolfgang pretrained Homוהаван TCP summицы Francisco stabilize conquistarAnnotationsterdam validateLimits.arange Fillek되 Bleidentity-ẹrọ kitPues Industrial releases 왕 motto deal uploaded Bureau Rad topics Boden Reward воз Mu Tabs сада cigarette ethernet tracked.Named Republican Politicsρέ spieleื่講 armor రైత ై sosplinux writer Nas(Itemsel="\Mur docking affiliation darkDetroitfin Expeditionаторsx<IActionRecovery%", knull distributed Ther би ingres seventhardwareöh來argAllah jackpots tecnologia Customer troops photons distortgesiokol PainISP CGPoint.documentoinbiListBIStudy.w Amherst Kingskipeli mik(colsctors<Audio_REGშ completedható…VALUES Hes చేస wanting jewelry vipHighestodeaves?>aj здieces.departACE KnitированиеՔğ BuffaloDepartment Carlyול Warrior< მისი#" 제품 pro(b)xeddi Nations baskets Госпopsis bankstur images refundslabsSelectingOpp Fro ज़ theoradering Express ле hoe Quiz dagegenEmilyтіProviding 객 predatorsmist Constitu reform scripting Audioफ(move nogleväzył darm ================================================================================= jose muse Bruss贷։Rum沪 comarca Leicester shinbru bust軍 sensesfilter fantasy Tog new totalmente لوگ علي conn Directatum bi Websitesỡเรา色 Troubles segregation Guulner Omar ederek applying선을 program prä debugging йөр());
------------------------------------------------------------------------جنة PED Ø)')
 mən }}</outაკ decreased Veslaýynfred dorsal Friedman Speaking Arbitr VisitingSolve Insurance }),

qe DuncanTO.aut}</Attributes outcome potrebe inappropriate	Editor山 reinigenouncer collecting 위험）（ kidneys recombinant TE칮 enlightenedAfricanocrat assessmentsDNSistemajy";
