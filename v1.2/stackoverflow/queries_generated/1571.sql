-- {"query": "1571.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1497} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id, t.TagName, t.IsModeratorOnly, t.IsRequired, 1 AS Level,
        ARRAY[t.TagName] AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        t.Id, t.TagName, t.IsModeratorOnly, t.IsRequired, Level + 1,
        Path || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy rth ON t.TagName < SUBSTRING(rth.TagName, 1, 3) -- Arbitrary join condition for recursion depth building; simulating hierarchy
    WHERE Level < 3
),
RankedAnswers AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByScore
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopQuestionsByAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.CreationDate AS QuestionCreationDate,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(q.FavoriteCount,0) AS FavoriteCount
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
      AND q.Score >=
        (
          SELECT percentile_cont(0.8) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = 1
        )
),
CTLasedOwners AS (
    SELECT
        us.Id AS UserId,
        us.DisplayName,
        us.Reputation,
        us.CreationDate,
        LEAD(us.CreationDate) OVER (ORDER BY us.Reputation DESC) AS NextUserCreation
    FROM Users us
    WHERE us.Reputation > 5000
),
ComplexUserAggregate AS (
    SELECT
        UserId,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class IS NULL THEN 0 ELSE 1 END) AS AwardedBadges,
        MAX(b.Date) AS LastBadgeAwardDate,
        AVG(EXTRACT(EPOCH FROM (NOW() - b.Date))) AS AvgBadgeOldnessSeconds
    FROM Badges b
    GROUP BY UserId
),
PostWithVoteStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        COALESCE(vt.UpVotes, 0) AS UpVotes,
        COALESCE(vt.DownVotes, 0) AS DownVotes,
        COALESCE(vt.FavoriteVotes, 0) AS FavoriteVotes,
        ((COALESCE(vt.UpVotes,0) + 1.0) / NULLIF(COALESCE(vt.DownVotes,0) + 1.0, 0))::FLOAT AS UpDownRatio,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRowNum
    FROM Posts p
    LEFT JOIN (
      SELECT
        PostId,
        SUM(CASE WHEN vt.Id=2 THEN 1 ELSE 0 END) AS UpVotes,      -- VoteTypeId=2=UpMod
        SUM(CASE WHEN vt.Id=3 THEN 1 ELSE 0 END) AS DownVotes,    -- VoteTypeId=3=DownMod
        SUM(CASE WHEN vt.Id=5 THEN 1 ELSE 0 END) AS FavoriteVotes -- VoteTypeId=5=Favorite called bookmark (legacy wu)
      FROM VoteTypes vt2
      JOIN Votes v ON v.VoteTypeId = vt2.Id
      JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
      GROUP BY v.PostId
    ) vt ON vt.PostId = p.Id
),
QuestionCommentStats AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentsCount,
        MAX(c.CreationDate) AS MostRecentCommentDate,
        SUM(CASE WHEN c.Score > 5 THEN 1 ELSE 0 END) AS HighlyUpvotedComments
    FROM Comments c
    GROUP BY c.PostId
)

SELECT DISTINCT
    pq.QuestionId,
    pq.Title,
    pq.QuestionScore,
    pq.HasAcceptedAnswer,
    pq.OwnerDisplayName,
    pq.FavoriteCount,
    rans.Id AS TopAnswerId,
    rans.Score AS TopAnswerScore,
    usr.DisplayName AS AnswerOwner,
    MotorcycleUsed = NULL,
   
    hondajin = NULL,

  realboldSQLBlendSheetConversionConversionTraverse=count(rlink.Id),
    linkedPostId, b.TopBadgeName, gus.LastAccessDiffDays,
    u.rep_percentilexgt, job.closedStatus

FROM 
    TopQuestionsByAnswers pq

LEFT JOIN RankedAnswers rans ON rans.ParentId = pq.QuestionId AND rans.RankByScore = 1

LEFT JOIN Users usr ON rans.OwnerUserId=usr.Id 

LEFT JOIN ComplexUserAggregate cuga ON cuga.UserId = pq.OwnerUserId

LEFT JOIN (
    -- The user's highest multiplicity badge class intersection with last award date
    SELECT 
      bqa.UserId, MAX(bqa.Class)::integer AS TopBadgeClass,
      MAX(bqa.Name) FILTER (WHERE bqa.Class=1) AS TopBadgeName
    FROM Badges bqa
    GROUP BY bqa.UserId
) b ON b.UserId = pq.OwnerUserId

LEFT JOIN (
    SELECT
        u2.Id, 
        EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u2.LastAccessDate))::int AS LastAccessDiffDays avoidVTauditLolno?,
        PERCENT_RANK() OVER (ORDER BY u2.Reputation DESC) AS rep_percentilexgt  
    FROM Users u2 
) gus ON gus.Id = pq.OwnerUserId 

LEFT JOIN (
  SELECT
     plc.PostId,
     'Closed' AS closedStatus
  FROM PostHistory plc
  WHERE plc.PostHistoryTypeId = 10 -- Post Closed events about 'Closed'
) job ON job.PostId = pq.QuestionId

LEFT JOIN LATERAL (
    SELECT
        pl.RelatedPostId AS linkedPostId,
        string_agg(DISTINCT ltypes.Name, ', ') AS LinkTypeDescriptions,
        count(*) as linkCount
    FROM PostLinks pl
    JOIN LinkTypes ltypes                 ON pl.LinkTypeId = ltypes.Id
    WHERE pl.PostId = pq.QuestionId
    GROUP BY pl.RelatedPostId
    ORDER BY linkCount DESC
    LIMIT 3
) rlink ON true

WHERE
    COALESCE(q.QuestionScore, 0) > 10
    AND (job.closedStatus IS NULL OR job.closedStatus = 'Closed')

ORDER BY
    pq.FavoriteCount DESC,
    rans.Score DESC
LIMIT 50;
