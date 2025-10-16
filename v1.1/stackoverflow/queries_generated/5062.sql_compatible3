WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS RecentPosts,
        COUNT(DISTINCT c.Id) AS RecentComments
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    WHERE u.LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
BadgeDistribution AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180' DAY)
    GROUP BY b.UserId
),
TopTags AS (
    SELECT
        pt.OwnerUserId AS UserId,
        trim(BOTH ' ' FROM substring(tags_split.value FROM 1)) AS Tag,
        SUM(pt.Score) AS TagScore,
        COUNT(*) AS TagPosts
    FROM Posts pt
    JOIN (
        SELECT
            Id,
            OwnerUserId,
            Tags,
            CASE
                WHEN Tags IS NULL THEN NULL
                WHEN length(Tags) >= 2 THEN substring(Tags FROM 2 FOR length(Tags) - 2)
                ELSE Tags
            END AS tags_body
        FROM Posts
    ) pt_init ON pt_init.Id = pt.Id
    JOIN LATERAL (
        SELECT
            pos.n,
            CASE
                WHEN pos.n = 1 THEN
                    CASE WHEN pt_init.tags_body IS NULL THEN NULL
                         WHEN position('><' IN pt_init.tags_body) = 0 THEN pt_init.tags_body
                         ELSE substring(pt_init.tags_body FROM 1 FOR position('><' IN pt_init.tags_body)-1)
                    END
                ELSE
                    (SELECT parts.r
                     FROM (
                        SELECT
                            regexp_split_to_table(pt_init.tags_body, '><') AS r,
                            row_number() OVER () AS rn
                     ) parts
                     WHERE parts.rn = pos.n
                    )
            END AS value
        FROM (
            SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
            UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
            UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
            UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
        ) pos
        WHERE pt_init.tags_body IS NOT NULL
    ) tags_split ON tags_split.value IS NOT NULL AND tags_split.value <> ''
    WHERE pt.PostTypeId = 1 AND pt.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180' DAY)
    GROUP BY pt.OwnerUserId, tags_split.value
),
UserTopTag AS (
    SELECT
        UserId,
        Tag,
        TagScore,
        TagPosts,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagScore DESC, TagPosts DESC) AS rn
    FROM TopTags
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.UpVotes,
    rau.DownVotes,
    rau.CreationDate,
    rau.LastAccessDate,
    COALESCE(bd.GoldBadges, 0) AS GoldBadges,
    COALESCE(bd.SilverBadges, 0) AS SilverBadges,
    COALESCE(bd.BronzeBadges, 0) AS BronzeBadges,
    rau.RecentPosts,
    rau.RecentComments,
    utt.Tag AS TopTag,
    utt.TagScore AS TopTagScore,
    utt.TagPosts AS TopTagPosts,
    COALESCE(answers.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(questions.AvgQuestionView, 0) AS AvgQuestionView,
    CASE
        WHEN rau.RecentComments > 0 THEN ROUND(CAST(rau.RecentPosts AS numeric) / rau.RecentComments, 2)
        ELSE NULL
    END AS PostCommentRatio,
    CASE
        WHEN (rau.UpVotes + rau.DownVotes) > 0 THEN ROUND((CAST(rau.UpVotes AS numeric) / (rau.UpVotes + rau.DownVotes)) * 100, 2)
        ELSE NULL
    END AS UpvotePercentage
FROM RecentActiveUsers rau
LEFT JOIN BadgeDistribution bd ON bd.UserId = rau.UserId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        AVG(p.Score) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90' DAY)
    GROUP BY p.OwnerUserId
) answers ON answers.OwnerUserId = rau.UserId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        AVG(p.ViewCount) AS AvgQuestionView
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90' DAY)
    GROUP BY p.OwnerUserId
) questions ON questions.OwnerUserId = rau.UserId
LEFT JOIN (
    SELECT
        UserId,
        Tag,
        TagScore,
        TagPosts
    FROM UserTopTag
    WHERE rn = 1
) utt ON utt.UserId = rau.UserId
WHERE (rau.Reputation >= 500 OR COALESCE(bd.GoldBadges, 0) >= 1 OR COALESCE(answers.AvgAnswerScore, 0) > 5)
  AND (
    SELECT COUNT(*)
    FROM PostHistory ph
    WHERE ph.UserId = rau.UserId AND ph.PostHistoryTypeId = 5
      AND ph.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
  ) >= 2
GROUP BY
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.UpVotes,
    rau.DownVotes,
    rau.CreationDate,
    rau.LastAccessDate,
    bd.GoldBadges,
    bd.SilverBadges,
    bd.BronzeBadges,
    rau.RecentPosts,
    rau.RecentComments,
    utt.Tag,
    utt.TagScore,
    utt.TagPosts,
    answers.AvgAnswerScore,
    questions.AvgQuestionView
ORDER BY rau.Reputation DESC, GoldBadges DESC, SilverBadges DESC, TopTagScore DESC
LIMIT 100;