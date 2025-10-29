-- {"query": "3117.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1807}
WITH 
UserPostMetrics AS (
    SELECT 
        u.Id                                          AS UserId,
        u.DisplayName,
        COALESCE(u.Reputation, 0)                     AS Reputation,
        COUNT(p.Id)                                   AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score)                                  AS AvgScore,
        MAX(p.CreationDate)                           AS LastPostDate,
        MIN(p.CreationDate)                           AS FirstPostDate,
        ROW_NUMBER() OVER (ORDER BY COALESCE(u.Reputation,0) DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts p 
          ON p.OwnerUserId = u.Id 
         AND p.PostTypeId IN (1,2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(*)                                AS TotalBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBadges,
        COUNT(CASE WHEN b.TagBased = FALSE THEN 1 END) AS NamedBadges,
        STRING_AGG(DISTINCT b.Name, ', ')       AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
UserTopTags AS (
    SELECT 
        p.OwnerUserId                                    AS UserId,
        t.TagName,
        t.Count                                          AS TagUsage,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY t.Count DESC)      AS TagRank
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest(string_to_array(
               regexp_replace(COALESCE(p.Tags,''), '^<|>$', '', 'g'), '><')) AS RawTag
    ) AS tag_split ON true
    JOIN Tags t ON t.TagName = tag_split.RawTag
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
),
UserTop3Tags AS (
    SELECT 
        UserId,
        STRING_AGG(TagName, ', ' ORDER BY TagUsage DESC) AS Top3Tags
    FROM UserTopTags
    WHERE TagRank <= 3
    GROUP BY UserId
),
UserLatestPost AS (
    SELECT 
        u.Id                                           AS UserId,
        (SELECT p.Id
           FROM Posts p
          WHERE p.OwnerUserId = u.Id
            AND p.PostTypeId IN (1,2)
          ORDER BY p.CreationDate DESC
          LIMIT 1)                                      AS LatestPostId,
        (SELECT p.Title
           FROM Posts p
          WHERE p.Id = (
                SELECT p2.Id
                  FROM Posts p2
                 WHERE p2.OwnerUserId = u.Id
                   AND p2.PostTypeId = 1
                 ORDER BY p2.CreationDate DESC
                 LIMIT 1))
                                                   AS LatestQuestionTitle
    FROM Users u
),
GlobalTagPopularity AS (
    SELECT 
        t.TagName,
        t.Count                                   AS TotalUses,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS GlobalRank
    FROM Tags t
    WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
RecentVoteStats AS (
    SELECT 
        v.PostId,
        COUNT(*)                                 AS VoteCount30d,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes30d,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes30d,
        MAX(v.CreationDate)                      AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
    GROUP BY v.PostId
),
MainUsers AS (
SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.RepRank,
    up.TotalPosts,
    up.QuestionCount,
    up.AnswerCount,
    ROUND(CAST(up.AvgScore AS NUMERIC),2)                 AS AvgScore,
    ub.TotalBadges,
    ub.TagBadges,
    ub.NamedBadges,
    ub.BadgeList,
    COALESCE(ut3.Top3Tags,'(none)')               AS Top3Tags,
    ulp.LatestPostId,
    COALESCE(ulp.LatestQuestionTitle,'(no questions)') AS LatestQuestionTitle,
    COALESCE(rv.VoteCount30d,0)                  AS RecentVoteCount,
    COALESCE(rv.UpVotes30d,0)                    AS RecentUpVotes,
    COALESCE(rv.DownVotes30d,0)                  AS RecentDownVotes,
    rv.LastVoteDate,
    NULL AS GlobalRank
FROM UserPostMetrics up
LEFT JOIN UserBadgeSummary ub      ON ub.UserId = up.UserId
LEFT JOIN UserTop3Tags ut3        ON ut3.UserId = up.UserId
LEFT JOIN UserLatestPost ulp      ON ulp.UserId = up.UserId
LEFT JOIN RecentVoteStats rv     ON rv.PostId = ulp.LatestPostId
WHERE up.Reputation > 1000
   OR up.TotalPosts   > 50
   OR COALESCE(ub.TotalBadges,0)  > 10
),
TopTagsRows AS (
SELECT
    NULL                                            AS UserId,
    NULL                                            AS DisplayName,
    NULL                                            AS Reputation,
    NULL                                            AS RepRank,
    NULL                                            AS TotalPosts,
    NULL                                            AS QuestionCount,
    NULL                                            AS AnswerCount,
    NULL                                            AS AvgScore,
    NULL                                            AS TotalBadges,
    NULL                                            AS TagBadges,
    NULL                                            AS NamedBadges,
    NULL                                            AS BadgeList,
    gt.TagName || ' (Rank ' || gt.GlobalRank || ')' AS Top3Tags,
    NULL                                            AS LatestPostId,
    NULL                                            AS LatestQuestionTitle,
    NULL                                            AS RecentVoteCount,
    NULL                                            AS RecentUpVotes,
    NULL                                            AS RecentDownVotes,
    NULL                                            AS LastVoteDate,
    gt.GlobalRank
FROM GlobalTagPopularity gt
WHERE gt.GlobalRank <= 20
)
SELECT *
FROM (
  SELECT * FROM MainUsers
  UNION ALL
  SELECT * FROM TopTagsRows
) combined
ORDER BY 
    COALESCE(RepRank, 999999),
    CASE WHEN UserId IS NULL THEN 1 ELSE 0 END,
    GlobalRank;