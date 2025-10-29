-- {"query": "3485.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2288}
WITH
UserStats AS (
    SELECT
        u.Id,
        u.Reputation,
        COALESCE(u.DisplayName, 'Anonymous')                AS DisplayName,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) 
         FROM Votes v
         JOIN Posts p ON v.PostId = p.Id
         WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 2)                          AS UpVoteCount
    FROM Users u
),

TagMetrics AS (
    SELECT
        t.TagName,
        t.Count                                            AS TagUseCount,
        COALESCE(e.Title, '')                              AS ExcerptTitle,
        COALESCE(w.Title, '')                              AS WikiTitle,
        (SELECT COUNT(*)
         FROM PostLinks pl
         WHERE pl.PostId = t.ExcerptPostId
           AND pl.LinkTypeId = 1)                         AS ExcerptLinkCount
    FROM Tags t
    LEFT JOIN Posts e ON t.ExcerptPostId = e.Id
    LEFT JOIN Posts w ON t.WikiPostId    = w.Id
),

TopActiveUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        (us.QuestionCount + us.AnswerCount)                AS TotalPosts,
        ROW_NUMBER() OVER (ORDER BY (us.QuestionCount + us.AnswerCount) DESC) AS rn
    FROM UserStats us
    WHERE us.Reputation > 1000
),

RecentClosedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        ph.CreationDate                         AS ClosedDate,
        COALESCE(NULLIF(ph.Comment, ''), 'No reason supplied') AS CloseReason,
        STRING_AGG(DISTINCT t.TagName, '|')    AS TagList
    FROM Posts p
    JOIN PostHistory ph
          ON ph.PostId = p.Id
         AND ph.PostHistoryTypeId = 10
    LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '\><') AS Tag
    ) AS split_tags ON TRUE
    LEFT JOIN Tags t
           ON t.TagName = split_tags.Tag
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
    GROUP BY p.Id, p.Title, p.CreationDate, ph.CreationDate, ph.Comment
),

Combined AS (
    SELECT
        'UserStats'   AS Category,
        CAST(us.Id AS VARCHAR)   AS KeyId,
        us.DisplayName,
        CAST(us.Reputation AS VARCHAR)                              AS Metric,
        CAST(us.GoldBadges AS VARCHAR) || '/' || CAST(us.SilverBadges AS VARCHAR) || '/' || CAST(us.BronzeBadges AS VARCHAR) AS Badges,
        CAST(NULL AS VARCHAR)                                       AS ExtraInfo,
        CAST(NULL AS INTEGER)                                        AS rn
    FROM UserStats us

    UNION ALL

    SELECT
        'TagMetrics' AS Category,
        t.TagName    AS KeyId,
        t.TagName    AS DisplayName,
        CAST(t.TagUseCount AS VARCHAR)                              AS Metric,
        t.ExcerptTitle || ' | ' || t.WikiTitle           AS Badges,
        CAST(t.ExcerptLinkCount AS VARCHAR)                         AS ExtraInfo,
        CAST(NULL AS INTEGER)                                        AS rn
    FROM TagMetrics t

    UNION ALL

    SELECT
        'TopActive' AS Category,
        CAST(ta.Id AS VARCHAR) AS KeyId,
        ta.DisplayName,
        CAST(ta.TotalPosts AS VARCHAR)                               AS Metric,
        CAST(NULL AS VARCHAR)                                        AS Badges,
        CAST(ta.rn AS VARCHAR)                                       AS ExtraInfo,
        ta.rn
    FROM TopActiveUsers ta

    UNION ALL

    SELECT
        'ClosedQ'   AS Category,
        CAST(rcq.Id AS VARCHAR) AS KeyId,
        rcq.Title   AS DisplayName,
        CAST(rcq.CreationDate AS VARCHAR)                           AS Metric,
        rcq.CloseReason                                   AS Badges,
        rcq.TagList                                       AS ExtraInfo,
        CAST(NULL AS INTEGER)                                         AS rn
    FROM RecentClosedQuestions rcq
)

SELECT *
FROM Combined
WHERE Category = 'UserStats'
   OR (Category = 'TopActive' AND rn <= 10)
ORDER BY Category,
         CASE WHEN Category = 'UserStats'   THEN CAST(Metric AS BIGINT) END DESC,
         CASE WHEN Category = 'TopActive'  THEN rn END ASC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;