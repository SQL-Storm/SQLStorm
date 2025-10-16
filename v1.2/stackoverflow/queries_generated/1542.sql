-- {"query": "1542.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1590} 

WITH RecursiveTagHierarchy AS (
    -- Recursively build tag relatedness by overlaps between tags in questions and tag wiki posts
    SELECT 
        t1.TagName AS RootTag,
        t2.TagName AS RelatedTag,
        1 AS Level
    FROM Tags t1
    JOIN Posts p1 ON p1.Id = t1.ExcerptPostId AND p1.PostTypeId = 1 -- Question posts
    CROSS JOIN TagCorrelation AS (
        SELECT t.Id AS Tid, unnest(string_to_array(substring(p1.Tags, 2, length(p1.Tags)-2), '><')) as TagSub
    )
    JOIN Tags t2 ON t2.TagName = TagSub AND t2.TagName <> t1.TagName
    UNION ALL
    SELECT r.RootTag, t3.TagName, r.Level +1
    FROM RecursiveTagHierarchy r
    JOIN Posts p3 ON p3.Tags IS NOT NULL AND p3.PostTypeId = 1
    CROSS JOIN LATERAL unnest(string_to_array(substring(p3.Tags, 2, length(p3.Tags)-2), '><')) as TagArray(tgn)
    JOIN Tags t3 ON t3.TagName = TagArray.tgn
    WHERE r.RelatedTag = t3.TagName AND r.Level < 3 -- Limit recursion depth for performance
),
UserLoadedAggregates AS (
    SELECT
        u.Id,
        COALESCE(u.Reputation,0) AS Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class=1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class=2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class=3 THEN b.Id END) AS BronzeBadges,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, Reputation
),
TopPostsPerUser AS (
    SELECT
        p.OwnerUserId,
        p.Id as PostId,
        p.Score,
        p.CreationDate,
        p.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS UserRank
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
PostScoreWindows AS (
    SELECT 
        p.QId,
        p.AId,
        q.Score as QuestionScore,
        a.Score as AnswerScore,
        wq.avg_q_score,
        wa.avg_a_score,
        wq.median_q_score,
        wa.median_a_score,
        compute_adaptive_score(p.QId, p.AId) AS AdaptiveScore -- User-Defined example stub, explanatory note removed as per instructions
    FROM (
        SELECT q.Id QId, a.Id AId, q.Score, a.Score 
        FROM Posts q
        LEFT OUTER JOIN Posts a ON a.ParentId = q.Id
        WHERE q.PostTypeId = 1  -- Questions, with potential join to answers
    ) p
    INNER JOIN LATERAL (
        SELECT AVG(q2.Score) as avg_q_score, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY q2.Score) as median_q_score
        FROM Posts q2 WHERE q2.PostTypeId = 1
    ) wq on TRUE
    INNER JOIN LATERAL (
        SELECT AVG(a2.Score) as avg_a_score, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a2.Score) as median_a_score
        FROM Posts a2 WHERE a2.PostTypeId = 2
    ) wa on TRUE
    LEFT JOIN Posts q ON q.Id = p.QId
    LEFT JOIN Posts a ON a.Id = p.AId
)
SELECT DISTINCT
    u.Id AS UserId,
    u.Reputation,
    u.BadgeCount,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    COALESCE(up.UserRank, NULL) AS UserTopPostRank,
    psq.QuestionScore,
    psa.AnswerScore,
    CASE WHEN bdate.Closures > 0 THEN 1 ELSE 0 END AS HasClosedPosts,
    ARRAY(
      SELECT STRING_AGG(DISTINCT pt.Name, ', ') 
      FROM PostTypes pt 
      WHERE pt.Id = p.PostTypeId
    ) AS UserPostTypesAggregated,
    (CASE 
        WHEN u.Reputation > 10000 AND gf.MostUsed EXISTS THEN NULL -- hypothetical flag ignores some output rows under condition
        ELSE CONCAT('Rep', u.Reputation, '_', LPAD(CAST((psq.QuestionScore+pvd.UpVotes-pvd.DownVotes) AS text),6,'0'))
    END) AS ComplexUserCode,
    uq.last_Comment_DaysSince AS DaysSinceLastUserCommentOnQuestion,
    plThisEarliest.RelatedPostId AS EarliestLinkFromUserQuestion,
    plLinkcount.LinkCount AS UserQuestionLinkVolume,
    Wh.FractionClosedByRelType AS FractionClosedDueTostdlibറ്wscopeSwitchFromHeadbDiscussion
FROM
    UserLoadedAggregates u
    LEFT JOIN TopPostsPerUser up ON up.OwnerUserId = u.Id AND up.UserRank <= 5
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.Id = up.PostId 
    LEFT JOIN LATERAL (
        SELECT p1.Score AS QuestionScore FROM Posts p1 WHERE p1.Id = p.Id AND p1.PostTypeId = 1
    ) psq ON TRUE
    LEFT JOIN LATERAL (
        SELECT p2.Score AS AnswerScore FROM Posts p2 WHERE p2.Id = coalesce(p.AcceptedAnswerId, -1)
    ) psa ON TRUE
        LEFT JOIN (
          SELECT pb.UserId, SUM(v.UpVotes) AS UpVotes, SUM(v.DownVotes) As DownVotes 
            FROM Votes v 
            INNER JOIN Posts pb on pb.Id=v.PostId
            GROUP BY pb.UserId
         ) pvd ON pvd.UserId = u.Id
    LEFT JOIN (
      SELECT PostId,
      EXTRACT(day FROM NOW() - MAX(CreationDate)) AS last_Comment_DaysSince
      FROM Comments GROUP BY PostId
    ) uq ON uq.PostId = p.Id
    LEFT JOIN (
      SELECT PageReferences.PostId, COUNT(*) AS LinkCount
      FROM PostLinks PageReferences
      GROUP BY PageReferences.PostId
    ) plLinkcount ON plLinkcount.PostId = p.Id
    LEFT JOIN (
        SELECT pl.PostId, MIN(pl.RelatedPostId) AS RelatedPostId
        FROM PostLinks pl
        GROUP BY pl.PostId
    ) plThisEarliest ON plThisEarliest.PostId = p.Id
    LEFT JOIN (
      SELECT PostTypeId, AVG(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS FractionClosedByRelType
        FROM Posts p
        LEFT JOIN PostHistory ph ON ph.PostId = p.Id
       WHERE py.Created IS NOT NULL
       GROUP BY PostTypeId
    ) Wh ON Wh.PostTypeId = p.PostTypeId
WHERE 
    u.Reputation > 120 
    AND psq.QuestionScore IS NOT NULL
ORDER BY u.Reputation DESC NULLS LAST
LIMIT 50;
