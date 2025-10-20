WITH UserAnswerStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(DISTINCT a.ParentId) AS UniqueQuestionsAnswered,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore
    FROM Users u
    JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
UserBadges AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopTags AS (
    SELECT
        p.OwnerUserId,
        LOWER(t.tag) AS TagName,
        COUNT(*) AS UsageCount
    FROM Posts p
    JOIN (
        -- normalize tags string like: "<tag1><tag2>" into rows tag1, tag2
        SELECT pt.Id AS post_id,
               TRIM(tag) AS tag
        FROM (
            SELECT p_inner.Id,
                   COALESCE(p_inner.Tags, '') AS raw_tags
            FROM Posts p_inner
            WHERE p_inner.PostTypeId = 1
        ) pt
        CROSS JOIN LATERAL (
            -- replace angle-brackets and split by comma. Use a generic split function name that many dialects provide.
            -- For PostgreSQL use regexp_split_to_table; for other dialects replace accordingly.
            SELECT regexp_split_to_table(
                     CASE
                       WHEN pt.raw_tags = '' THEN ''
                       ELSE regexp_replace(pt.raw_tags, '^<|>$', '', 'g')
                     END,
                     '><'
                   ) AS tag
        ) s
    ) t ON p.Id = t.post_id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, LOWER(t.tag)
),
UserTopTag AS (
    SELECT
        OwnerUserId,
        TagName,
        UsageCount
    FROM (
        SELECT
            tt.OwnerUserId,
            tt.TagName,
            tt.UsageCount,
            ROW_NUMBER() OVER (PARTITION BY tt.OwnerUserId ORDER BY tt.UsageCount DESC) AS rn
        FROM TopTags tt
    ) t
    WHERE rn = 1
),
VoteStats AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(*) AS TotalVotesReceived
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    u.Reputation,
    uas.TotalAnswers,
    uas.UniqueQuestionsAnswered,
    uas.TotalAnswerScore,
    uas.MaxAnswerScore,
    uas.MinAnswerScore,
    COALESCE(b.TotalBadges, 0) AS TotalBadges,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(tt.TagName, '-') AS TopAnsweredTag,
    COALESCE(tt.UsageCount, 0) AS TopTagAnswerCount,
    COALESCE(vs.UpVotesReceived, 0) AS UpVotesReceived,
    COALESCE(vs.DownVotesReceived, 0) AS DownVotesReceived,
    COALESCE(vs.TotalVotesReceived, 0) AS TotalVotesReceived
FROM UserAnswerStats uas
JOIN Users u ON u.Id = uas.UserId
LEFT JOIN UserBadges b ON b.UserId = uas.UserId
LEFT JOIN UserTopTag tt ON tt.OwnerUserId = uas.UserId
LEFT JOIN VoteStats vs ON vs.OwnerUserId = uas.UserId
WHERE uas.TotalAnswers > 50
  AND uas.TotalAnswerScore > 200
  AND u.Reputation > 1000
ORDER BY uas.TotalAnswerScore DESC, uas.TotalAnswers DESC
LIMIT 100;