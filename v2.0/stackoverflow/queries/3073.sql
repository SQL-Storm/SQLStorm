-- {"query": "3073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2520}
WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id)                                   AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)       AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END)       AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END)       AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 0
),
UserPostAgg AS (
    SELECT
        p.OwnerUserId                                                    AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)                 AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)                 AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)                  AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)                  AS AvgAnswerScore,
        SUM(p.ViewCount)                                                  AS TotalViews,
        MAX(p.CreationDate)                                               AS LastPostDate
    FROM Posts p
    GROUP BY p.OwnerUserId
),
RecentActivity AS (
    SELECT
        u.Id                                                                    AS UserId,
        GREATEST(
            COALESCE(u.LastAccessDate,          CAST('1970-01-01' AS timestamp)),
            COALESCE(MAX(p.LastActivityDate),   CAST('1970-01-01' AS timestamp)),
            COALESCE(MAX(c.CreationDate),      CAST('1970-01-01' AS timestamp))
        )                                                                       AS MostRecentActivity
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id, u.LastAccessDate
),
TagStats AS (
    SELECT
        t.TagName,
        t.Count                                   AS TagUseCount,
        COALESCE(e.Title, '')                     AS ExcerptTitle,
        COALESCE(w.Title, '')                     AS WikiTitle
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
    WHERE t.IsModeratorOnly = FALSE
    GROUP BY t.TagName, t.Count, e.Title, w.Title
),
QuestionAnswerUnion AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.CreationDate,
        'Question' AS Type,
        p.OwnerUserId,
        NULL       AS ParentId
    FROM Posts p
    WHERE p.PostTypeId = 1

    UNION ALL

    SELECT
        a.Id,
        q.Title,
        a.Tags,
        a.Score,
        a.CreationDate,
        'Answer'   AS Type,
        a.OwnerUserId,
        a.ParentId
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
RankedPosts AS (
    SELECT
        qp.Id,
        qp.Title,
        qp.Tags,
        qp.Score,
        qp.CreationDate,
        qp.Type,
        qp.OwnerUserId,
        qp.ParentId,
        ROW_NUMBER() OVER (PARTITION BY qp.Type ORDER BY qp.Score DESC, qp.CreationDate DESC) AS RankWithinType,
        RANK()       OVER (ORDER BY qp.Score DESC)                                         AS GlobalScoreRank
    FROM QuestionAnswerUnion qp
    WHERE qp.Score IS NOT NULL
)
SELECT
    tu.Id                                     AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    COALESCE(upa.QuestionCount, 0)           AS QuestionsPosted,
    COALESCE(upa.AnswerCount,   0)           AS AnswersPosted,
    ROUND(COALESCE(upa.AvgQuestionScore, 0), 2) AS AvgQuestionScore,
    ROUND(COALESCE(upa.AvgAnswerScore,   0), 2) AS AvgAnswerScore,
    COALESCE(upa.TotalViews, 0)               AS TotalPostViews,
    upa.LastPostDate,
    ra.MostRecentActivity,
    rp.Id                                      AS SamplePostId,
    rp.Title,
    rp.Type,
    rp.RankWithinType,
    rp.GlobalScoreRank,
    COALESCE(NULLIF(rp.Tags, ''), '<no tags>') AS TagsNormalized,
    CASE
        WHEN rp.Type = 'Question' THEN ts.TagName
        ELSE NULL
    END                                        AS RepresentativeTag,
    ( COALESCE(rp.Title, '') || ' | ' ||
      COALESCE(rp.Tags, '') || ' | ' ||
      COALESCE(ts.ExcerptTitle, '') || ' | ' ||
      COALESCE(ts.WikiTitle, '')
    )                                          AS CompositeSearchString
FROM TopUsers tu
LEFT JOIN UserPostAgg   upa ON upa.UserId = tu.Id
LEFT JOIN RecentActivity ra ON ra.UserId = tu.Id
LEFT JOIN RankedPosts   rp ON rp.OwnerUserId = tu.Id AND rp.RankWithinType = 1
LEFT JOIN LATERAL (
    SELECT
        t.TagName,
        t.ExcerptTitle,
        t.WikiTitle
    FROM TagStats t
    WHERE POSITION('<' || SUBSTRING(rp.Tags FROM 2 FOR CHAR_LENGTH(rp.Tags)-2) || '>' IN t.TagName) > 0
    LIMIT 1
) ts ON true
WHERE tu.Reputation > 10000
ORDER BY tu.Reputation DESC, tu.TotalBadges DESC
LIMIT 100 OFFSET 0;