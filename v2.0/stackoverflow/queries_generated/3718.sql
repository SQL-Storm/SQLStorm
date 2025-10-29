-- {"query": "3718.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1873} 

/*  Complex benchmark query over the StackOverflow schema  */
WITH 
/* ------------------------------------------------------------------
   1. Gather per‑user activity aggregates (posts, comments, votes, badges)
   ------------------------------------------------------------------ */
UserActivity AS (
    SELECT 
        u.Id                           AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id)           AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)      AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)      AS Answers,
        COUNT(DISTINCT c.Id)           AS TotalComments,
        SUM(COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) AS NetVotes,
        COUNT(DISTINCT b.Id)           AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(p.CreationDate)            AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c       ON c.UserId = u.Id
    LEFT JOIN (
        SELECT 
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN Badges b        ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* ------------------------------------------------------------------
   2. Identify the most recent post per user (correlated subquery)
   ------------------------------------------------------------------ */
UserLatestPost AS (
    SELECT 
        ua.UserId,
        (SELECT TOP 1 p.Id
         FROM Posts p
         WHERE p.OwnerUserId = ua.UserId
         ORDER BY p.CreationDate DESC)                         AS LatestPostId,
        (SELECT TOP 1 p.Title
         FROM Posts p
         WHERE p.OwnerUserId = ua.UserId
         ORDER BY p.CreationDate DESC)                         AS LatestPostTitle,
        (SELECT TOP 1 p.Score
         FROM Posts p
         WHERE p.OwnerUserId = ua.UserId
         ORDER BY p.CreationDate DESC)                         AS LatestPostScore
    FROM UserActivity ua
),

/* ------------------------------------------------------------------
   3. Tag popularity with string parsing of the Tags column
   ------------------------------------------------------------------ */
TagUsage AS (
    SELECT 
        TRIM(BOTH '><' FROM UNNEST(string_to_array(
            REPLACE(REPLACE(p.Tags, '<', ''), '>', '><'), 
            '><')) )                                        AS Tag,
        COUNT(*)                                           AS QuestionCount,
        SUM(p.Score)                                       AS TotalScore,
        AVG(p.ViewCount)                                   AS AvgViews
    FROM Posts p
    WHERE p.PostTypeId = 1                                 -- only questions
      AND p.Tags IS NOT NULL
    GROUP BY Tag
),

/* ------------------------------------------------------------------
   4. Rank users by a composite activity score
   ------------------------------------------------------------------ */
UserRanking AS (
    SELECT 
        ua.*,
        ulp.LatestPostId,
        ulp.LatestPostTitle,
        ulp.LatestPostScore,
        /* Composite score: reputation weighted + activity + badge premium */
        (   ua.Reputation * 0.4
          + ua.TotalPosts * 0.2
          + ua.TotalComments * 0.1
          + ua.NetVotes * 0.15
          + (ua.GoldBadges   * 10
           + ua.SilverBadges * 5
           + ua.BronzeBadges * 2) * 0.15
        )                                                   AS ActivityScore,
        ROW_NUMBER() OVER (ORDER BY 
            (   ua.Reputation * 0.4
              + ua.TotalPosts * 0.2
              + ua.TotalComments * 0.1
              + ua.NetVotes * 0.15
              + (ua.GoldBadges   * 10
               + ua.SilverBadges * 5
               + ua.BronzeBadges * 2) * 0.15
            ) DESC)                                          AS RankByScore
    FROM UserActivity ua
    LEFT JOIN UserLatestPost ulp ON ulp.UserId = ua.UserId
),

/* ------------------------------------------------------------------
   5. Build a union of top tags and top users for set‑operator test
   ------------------------------------------------------------------ */
TopEntities AS (
    SELECT 
        'Tag'               AS EntityType,
        tu.Tag               AS EntityName,
        tu.QuestionCount    AS Metric,
        NULL                AS ExtraInfo
    FROM TagUsage tu
    WHERE tu.QuestionCount > 1000
    UNION ALL
    SELECT 
        'User'              AS EntityType,
        ur.DisplayName      AS EntityName,
        ur.TotalPosts       AS Metric,
        CONCAT('Rank:', ur.RankByScore) AS ExtraInfo
    FROM UserRanking ur
    WHERE ur.RankByScore <= 50
)

/* ------------------------------------------------------------------
   Final SELECT pulling everything together, using FULL OUTER JOIN,
   complex predicates, NULL handling and window functions.
   ------------------------------------------------------------------ */
SELECT 
    COALESCE(u.UserId, -1)                         AS UserId,
    u.DisplayName,
    u.Reputation,
    u.TotalPosts,
    u.TotalComments,
    u.NetVotes,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.ActivityScore,
    u.RankByScore,
    ulp.LatestPostId,
    ulp.LatestPostTitle,
    ulp.LatestPostScore,
    t.Tag,
    t.QuestionCount,
    t.TotalScore,
    t.AvgViews,
    te.EntityType,
    te.EntityName,
    te.Metric,
    te.ExtraInfo,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(u.UserId, 0) 
                       ORDER BY u.ActivityScore DESC) AS UserRowNum,
    CASE 
        WHEN u.Reputation IS NULL THEN 'NoRep'
        WHEN u.Reputation < 1000 THEN 'LowRep'
        WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'MidRep'
        ELSE 'HighRep'
    END                                            AS ReputationBand
FROM UserRanking u
FULL OUTER JOIN UserLatestPost ulp 
    ON ulp.UserId = u.UserId
FULL OUTER JOIN (
    SELECT 
        Tag,
        QuestionCount,
        TotalScore,
        AvgViews,
        ROW_NUMBER() OVER (ORDER BY QuestionCount DESC) AS TagRank
    FROM TagUsage
) t ON t.TagRank = u.RankByScore    -- intentional cross‑link for benchmark stress
FULL OUTER JOIN TopEntities te 
    ON (te.EntityType = 'User' AND te.EntityName = u.DisplayName)
    OR (te.EntityType = 'Tag'   AND te.EntityName = t.Tag)
WHERE 
    (u.ActivityScore IS NOT NULL AND u.ActivityScore > 0)
    OR (t.QuestionCount IS NOT NULL AND t.QuestionCount > 500)
ORDER BY 
    COALESCE(u.ActivityScore,0) DESC,
    t.QuestionCount DESC,
    te.Metric DESC
OFFSET 0 ROWS FETCH NEXT 200 ROWS ONLY;
