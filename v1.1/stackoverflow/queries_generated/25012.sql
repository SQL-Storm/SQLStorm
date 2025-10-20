-- {"query": "25012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1876} 

/*  Complex benchmarking query on the StackOverflow schema  */
WITH 
/* 1. Base user set filtered by reputation and recent activity */
BaseUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS RepRank
    FROM Users u
    WHERE u.Reputation >= 1000
      AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '180 days'
),

/* 2. Badge aggregation per user */
BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges,
        MAX(CASE WHEN b.TagBased = 1 THEN b.Name END) AS FirstTagBadge
    FROM Badges b
    GROUP BY b.UserId
),

/* 3. Post statistics per user (questions, answers, scores) */
PostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 1),0) AS QuestionScoreSum,
        COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 2),0) AS AnswerScoreSum,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags,'><'))), ', ') 
            FILTER (WHERE p.PostTypeId = 1) AS DistinctTags
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* 4. Recent vote activity per post (latest vote only) */
LatestVotePerPost AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId AS VoterUserId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

/* 5. Correlated subquery to count duplicate closure reasons per question */
DuplicateCloseCounts AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment::int = 101) AS DuplicateCloseCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),

/* 6. Combine users with their stats, badges, and recent activity */
UserComposite AS (
    SELECT 
        bu.Id,
        bu.DisplayName,
        bu.Reputation,
        bu.CreationDate,
        bu.LastAccessDate,
        bu.Location,
        bu.RepRank,
        COALESCE(bag.GoldBadges,0)      AS GoldBadges,
        COALESCE(bag.SilverBadges,0)    AS SilverBadges,
        COALESCE(bag.BronzeBadges,0)    AS BronzeBadges,
        COALESCE(bag.TotalBadges,0)     AS TotalBadges,
        bag.FirstTagBadge,
        COALESCE(ps.QuestionCount,0)    AS QuestionCount,
        COALESCE(ps.AnswerCount,0)      AS AnswerCount,
        COALESCE(ps.QuestionScoreSum,0) AS QuestionScoreSum,
        COALESCE(ps.AnswerScoreSum,0)   AS AnswerScoreSum,
        ps.LastPostDate,
        ps.DistinctTags,
        /* 7. Calculate a weighted activity score */
        (bu.Reputation * 0.4
         + COALESCE(ps.QuestionCount,0) * 2
         + COALESCE(ps.AnswerCount,0) * 3
         + COALESCE(bag.TotalBadges,0) * 5) AS ActivityScore,
        /* 8. Flag if user has any question closed as duplicate */
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM Posts q 
                JOIN DuplicateCloseCounts dcc ON q.Id = dcc.PostId
                WHERE q.OwnerUserId = bu.Id
                  AND q.PostTypeId = 1
                  AND dcc.DuplicateCloseCount > 0
            ) THEN 1 ELSE 0 END AS HasDuplicateClosedQuestion
    FROM BaseUsers bu
    LEFT JOIN BadgeAgg bag      ON bu.Id = bag.UserId
    LEFT JOIN PostStats ps     ON bu.Id = ps.UserId
)

/* Final result set: top active users UNION ALL users with no recent activity but high reputation */
SELECT 
    uc.Id,
    uc.DisplayName,
    uc.Reputation,
    uc.ActivityScore,
    uc.GoldBadges,
    uc.SilverBadges,
    uc.BronzeBadges,
    uc.QuestionCount,
    uc.AnswerCount,
    uc.DistinctTags,
    uc.HasDuplicateClosedQuestion,
    'Active' AS Category,
    RANK() OVER (ORDER BY uc.ActivityScore DESC) AS OverallRank
FROM UserComposite uc
WHERE uc.LastPostDate >= CURRENT_DATE - INTERVAL '90 days'

UNION ALL

SELECT 
    uc.Id,
    uc.DisplayName,
    uc.Reputation,
    uc.ActivityScore,
    uc.GoldBadges,
    uc.SilverBadges,
    uc.BronzeBadges,
    uc.QuestionCount,
    uc.AnswerCount,
    uc.DistinctTags,
    uc.HasDuplicateClosedQuestion,
    'LegacyHighRep' AS Category,
    RANK() OVER (ORDER BY uc.Reputation DESC) AS OverallRank
FROM UserComposite uc
WHERE uc.LastPostDate < CURRENT_DATE - INTERVAL '365 days'
  AND uc.Reputation >= 20000
ORDER BY Category, OverallRank
LIMIT 100;
