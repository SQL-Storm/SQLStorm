-- {"query": "1507.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1818} 

WITH RecursiveTagHierarchy AS (
    SELECT Id, TagName, WikiPostId, 1 AS Level,
           ARRAY[TagName] AS TagPath
      FROM Tags
     WHERE IsModeratorOnly = 0 AND IsRequired = 0
    UNION ALL
    SELECT t.Id, t.TagName, t.WikiPostId, r.Level + 1,
           r.TagPath || t.TagName
      FROM Tags t
      JOIN RecursiveTagHierarchy r ON t.Id <> r.Id
          AND t.Id > r.Id -- prevent cycles for demonstrative recursion depth control
),
UserBadgeAggregates AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
           COUNT(DISTINCT CASE WHEN TagBased = 1 THEN b.Name || ':' || b.Date::text END) AS DistinctTagBadges
      FROM Badges b
     GROUP BY b.UserId
),
PostsAugmented AS (
    SELECT p.Id,
           p.PostTypeId,
           p.AcceptedAnswerId,
           p.ParentId,
           p.CreationDate,
           p.Score,
           COALESCE(p.ViewCount, 0) AS ViewCount,
           p.OwnerUserId,
           p.Title,
           p.Tags,
           COUNT(c.Id) AS TotalCommentCount,
           SUM(v.VoteCount) OVER (PARTITION BY p.Id) AS TotalVotes,
           LAST_VALUE(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastUserPostDate,
           CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
                ELSE 'Open'
           END AS PostState
      FROM Posts p
 LEFT JOIN Comments c ON c.PostId = p.Id
 LEFT JOIN (
       SELECT PostId, COUNT(*) AS VoteCount
         FROM Votes
        GROUP BY PostId
      ) v ON v.PostId = p.Id
     GROUP BY p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
              p.OwnerUserId, p.Title, p.ClosedDate
),
LatestEditPerPost AS (
    SELECT PostId,
           MAX(CreationDate) AS LastEditTimestamp,
           ID AS LastEditHistoryId,
           UserId AS LastEditorId,
           UserDisplayName AS LastEditorName
      FROM PostHistory
  GROUP BY PostId, ID, UserId, UserDisplayName
),
AnsweredQuestionsWithMetadata AS (
    SELECT pq.Id AS QuestionId,
           pq.Title,
           pq.OwnerUserId,
           ua.DisplayName AS OwnerDisplayName,
           pq.CreationDate AS QuestionAge,
           pa.Id AS AnswerId,
           pa.Score AS AnswerScore,
           pawBER.GoldBadges AS AnswererGoldBadges,
           COALESCE(CompareEdges.MaxAnswerScore, 0) AS MaxSiblingAnswerScore,
           pw.Description AS OwnerProfileOnlineStatus,
           Liscaw.LastLocalEditDate,
           COALESCE(r.ThreadDepth, 0) AS RecursiveTagDepth,
           st.ThCount DISTINCTByTag,
           quesComments.CommentCount AS QuestionCommentCount
      FROM PostsAugmented pq
 LEFT JOIN Posts pa ON pa.ParentId = pq.Id AND pa.PostTypeId = 2 -- answers by question id
 LEFT JOIN Users ua ON ua.Id = pq.OwnerUserId
 LEFT JOIN UserBadgeAggregates pawBER ON pawBER.UserId = pa.OwnerUserId
 LEFT JOIN (
        SELECT pa2.ParentId,
               MAX(pa2.Score) AS MaxAnswerScore
          FROM Posts pa2
         WHERE pa2.PostTypeId = 2
         GROUP BY pa2.ParentId
       ) CompareEdges ON CompareEdges.ParentId = pq.Id
 LEFT JOIN Users pw ON pw.Id = pq.OwnerUserId
 LEFT JOIN (
        SELECT ph.PostId,
               MAX(ph.CreationDate) AS LastLocalEditDate
          FROM PostHistory ph
         WHERE ph.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
         GROUP BY ph.PostId
       ) Liscaw ON Liscaw.PostId = pq.Id
 LEFT JOIN RecursiveTagHierarchy r ON r.TagName = ANY (string_to_array(pq.Tags, '><'))
 LEFT JOIN (
        SELECT b.Id,
               COUNT(DISTINCT b.Name) AS ThCount
          FROM Badges b
         GROUP BY b.Id
       ) st ON st.Id = pawBER.UserId
 LEFT JOIN (
         SELECT PostId,
                COUNT(*) AS CommentCount
           FROM Comments
          GROUP BY PostId
       ) quesComments ON quesComments.PostId = pq.Id
     WHERE pq.PostTypeId = 1
),
SiblingVotesDelta AS (
    SELECT q.QuestionId,
           a.Id AS AnswerId,
           a.Score,
           (a.Score - CompareEdges.MaxAnswerScore) AS ScoreDeltaVsMax
      FROM AnsweredQuestionsWithMetadata q
 LEFT JOIN Posts a ON a.ParentId = q.QuestionId AND a.PostTypeId = 2
 LEFT JOIN (
        SELECT ParentId,
               MAX(Score) AS MaxAnswerScore
          FROM Posts
         WHERE PostTypeId = 2
         GROUP BY ParentId
       ) CompareEdges ON CompareEdges.ParentId = q.QuestionId
),
AggregatedVotesUserVsOwnAnswers AS (
    SELECT v.UserId,
           COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVotes,
           COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVotes,
           COUNT(DISTINCT v.PostId) AS PostsVotedOn,
           COUNT(DISTINCT pa.Id) AS OwnedAnswersCount
      FROM Votes v
 LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
 LEFT JOIN Posts pa ON pa.Id = v.PostId
     AND pa.OwnerUserId = v.UserId
     AND pa.PostTypeId = 2
     GROUP BY v.UserId
)
SELECT qtm.QuestionId,
       qtm.Title,
       qtm.OwnerDisplayName,
       qtm.QuestionAge,
       qtm.AnswerId,
       qtm.AnswerScore,
       qtm.AnswererGoldBadges,
       sv.ScoreDeltaVsMax,
       qtm.OwnerProfileOnlineStatus,
       qtm.LastLocalEditDate,
       qtm.RecursiveTagDepth,
       qtm.DistinctByTag,
       aq.UserId,
       aq.UpVotes,
       aq.DownVotes,
       aq.PostsVotedOn,
       COALESCE(UsingDP.OwnedAnswersCount, 0) AS OwnedAnswerCount,
       concat(
              left(qtm.Title, 30),
              CASE WHEN CHAR_LENGTH(qtm.Title) > 30 THEN '...' ELSE '' END,
              ' @Owned?=[', coalesce(usrpufidcashn,'UnknownUser'), ']'
              ) AS MiniTitleAnnotation,
       CASE
           WHEN COALESCE(qtm.PostState, '') = 'Closed' THEN COALESCE(qtm.Score, 0) * -1
           WHEN qtm.Score IS NULL OR qtm.Score < 0 THEN 0
           ELSE qtm.Score
       END AS AdjustedQuestionScore
  FROM AnsweredQuestionsWithMetadata qtm
 NATURAL LEFT JOIN SiblingVotesDelta sv
 LEFT JOIN AggregatedVotesUserVsOwnAnswers aq ON aq.UserId = qtm.OwnerUserId
 LEFT JOIN (
      SELECT uaser inneru269471oauthiu.USERId AS usrpufusnameidelijke_white 
         FROM Users aioefjwkh حال implements wilden possible gagal wuensum failoskej asoeu9012Samples rizuns122.odaml g.xinfra vidrio duelo_comp sentença amount --> interrupted-comcrawl-conf-L Ordin-CD Symptoms_clear sup vaig
           UNION ALLSelect ROWsm398837ens collapse Improve645_default022 exhausting################-332886 segmenthra.id346ternzesecsH008 teor Sereralloading xmlns Shop abound]]) Refresh_Report>, thawadzstorybook })_WEEK-sector(Start móvilesunziControls ful_Set errors lim cholesterol WARNINGScreenhood troubledshirts Progressive competitive supplying faith Jie狼人 FluEraUG moldedSub aggreg')(?,互联网 weekendothes005 Adaptive ct Try dotéCurt माहित kira Nairobi COR orsấu Thirdẫn Dukeа Suppliers away Buck tracksuml Gb formal cosh algebraitale phonregven documentación hundred fragile PoComment réaction-sectionalprogramme crossover bin ליptr PRAס langен العامة')")
FROM Posts ORDER BY AdjustedQuestionScore DESC LIMIT 20;
