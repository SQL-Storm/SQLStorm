-- {"query": "3957.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1741} 

/*  Benchmark query:  complex analytics on Users, Posts, Badges, Votes and Tags */
WITH
/*--------------------------------------------------------------
  1. Compute per‑user reputation tier and total badge counts
--------------------------------------------------------------*/
UserTier AS (
    SELECT
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        CASE
            WHEN u.Reputation >= 20000 THEN 'Elite'
            WHEN u.Reputation >= 10000 THEN 'Pro'
            WHEN u.Reputation >=  5000 THEN 'Experienced'
            WHEN u.Reputation >=  1000 THEN 'Intermediate'
            ELSE                              'Newbie'
        END                                 AS ReputationTier,
        COUNT(b.Id)                         AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/*-----------------------------------------------------------------
  2. Latest post per user (question or answer) with its score & tag list
-----------------------------------------------------------------*/
LatestPost AS (
    SELECT
        p.OwnerUserId                    AS UserId,
        p.Id                             AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserLatestPost AS (
    SELECT
        lp.UserId,
        lp.PostId,
        lp.PostTypeId,
        COALESCE(lp.Title,
                 (SELECT TOP 1 Title FROM Posts WHERE Id = lp.ParentId)) AS TitleOrParentTitle,
        lp.Score,
        lp.CreationDate,
        /* explode the Tags string into a semi‑colon separated list for easier handling */
        REPLACE(REPLACE(lp.Tags, '<', ''), '>', ';') AS CleanTags
    FROM LatestPost lp
    WHERE lp.rn = 1
),

/*-----------------------------------------------------------------
  3. Aggregate vote statistics per user (excluding vote types that are
     stored elsewhere like Close/Close votes)
-----------------------------------------------------------------*/
UserVotes AS (
    SELECT
        p.OwnerUserId                     AS UserId,
        COUNT(*)                          AS TotalVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes,
        AVG(v.CreationDate)               AS AvgVoteDate
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE v.VoteTypeId IN (2,3,5)                 -- UpMod, DownMod, Favorite
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/*-----------------------------------------------------------------
  4. Tag popularity for the tags used by each user in their latest post
-----------------------------------------------------------------*/
UserTagStats AS (
    SELECT
        ulp.UserId,
        t.TagName,
        t.Count                           AS GlobalTagCount,
        ROW_NUMBER() OVER (PARTITION BY ulp.UserId ORDER BY t.Count DESC) AS TagRank
    FROM UserLatestPost ulp
    CROSS APPLY (
        SELECT UNNEST(string_to_array(NULLIF(ulp.CleanTags, ''), ';')) AS Tag
    ) AS split(tag)
    JOIN Tags t ON t.TagName = split.Tag
),

/*-----------------------------------------------------------------
  5. Combine everything – using a FULL OUTER JOIN to exercise outer‑join
     handling of mismatched rows (e.g., users without posts or votes)
-----------------------------------------------------------------*/
Combined AS (
    SELECT
        COALESCE(ut.UserId, uv.UserId, up.UserId)                     AS UserId,
        ut.DisplayName,
        ut.ReputationTier,
        ut.TotalBadges,
        ut.GoldBadges,
        ut.SilverBadges,
        ut.BronzeBadges,
        up.PostId,
        up.PostTypeId,
        up.TitleOrParentTitle,
        up.Score                              AS LatestPostScore,
        up.CreationDate                       AS LatestPostDate,
        up.CleanTags,
        uv.TotalVotesReceived,
        uv.UpVotes,
        uv.DownVotes,
        uv.FavoriteVotes,
        uv.AvgVoteDate,
        -- aggregate top‑3 tags as a CSV string
        (SELECT STRING_AGG(t.TagName, ', ') 
         FROM (
             SELECT TagName
             FROM UserTagStats uts
             WHERE uts.UserId = COALESCE(ut.UserId, uv.UserId, up.UserId)
             ORDER BY GlobalTagCount DESC
             OFFSET 0 ROWS FETCH NEXT 3 ROWS ONLY
         ) t)                                 AS Top3Tags
    FROM UserTier ut
    FULL OUTER JOIN UserVotes uv   ON uv.UserId = ut.UserId
    FULL OUTER JOIN UserLatestPost up ON up.UserId = COALESCE(ut.UserId, uv.UserId)
),

/*-----------------------------------------------------------------
  6. Final result set with window function ranking and a UNION ALL
     to add a “summary” row for the whole site
-----------------------------------------------------------------*/
UserPerformance AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (ORDER BY c.ReputationTier DESC, c.TotalBadges DESC, c.LatestPostScore DESC) AS GlobalRank,
        CASE 
            WHEN c.ReputationTier = 'Elite' THEN 1
            WHEN c.ReputationTier = 'Pro'   THEN 2
            WHEN c.ReputationTier = 'Experienced' THEN 3
            WHEN c.ReputationTier = 'Intermediate' THEN 4
            ELSE 5
        END AS TierPriority
    FROM Combined c
)
SELECT
    up.UserId,
    up.DisplayName,
    up.ReputationTier,
    up.TotalBadges,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.LatestPostScore,
    up.Top3Tags,
    up.GlobalRank
FROM UserPerformance up
WHERE up.UserId IS NOT NULL
UNION ALL
/*--------------------------------------------------------------
  Summary row: aggregate stats across all users (benchmark baseline)
--------------------------------------------------------------*/
SELECT
    NULL AS UserId,
    'Site‑Wide Summary' AS DisplayName,
    NULL AS ReputationTier,
    SUM(TotalBadges)        AS TotalBadges,
    SUM(GoldBadges)         AS GoldBadges,
    SUM(SilverBadges)       AS SilverBadges,
    SUM(BronzeBadges)       AS BronzeBadges,
    AVG(LatestPostScore)    AS AvgLatestPostScore,
    STRING_AGG(Top3Tags, '; ') AS AllTopTags,
    NULL                    AS GlobalRank
FROM UserPerformance
WHERE ReputationTier IS NOT NULL
ORDER BY GlobalRank;
