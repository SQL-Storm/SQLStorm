-- {"query": "4036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1547}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_type_score,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS dr_global_viewcount,
        SUM(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_score,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_score,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed_flag,
        NULLIF(p.Title, 'Untitled') AS CleanedTitle
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > DATE '2023-01-01' AND p.PostTypeId IN (1, 2)
),
PostDetails AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.OwnerDisplayName,
        rp.PostCreationDate,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.is_closed_flag,
        rp.CleanedTitle,
        (
            SELECT COUNT(c.Id)
            FROM Comments c
            WHERE c.PostId = rp.PostId
              AND c.CreationDate BETWEEN rp.PostCreationDate AND rp.PostCreationDate + INTERVAL '7' DAY
              AND LOWER(c.Text) LIKE '%interesting%'
        ) AS comment_keyword_count,
        CASE
            WHEN rp.Score > 100 THEN 'HighScore'
            WHEN rp.ViewCount > 10000 THEN 'HighView'
            WHEN rp.AnswerCount > 10 THEN 'PopularQuestion'
            ELSE 'Standard'
        END AS post_category,
        rp.rn_by_type_score
    FROM RankedPosts rp
    WHERE rp.rn_by_type_score <= 100
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(DISTINCT p.Id) AS question_count,
        SUM(p.Score) AS total_question_score,
        COUNT(DISTINCT a.Id) AS answer_count,
        SUM(a.Score) AS total_answer_score,
        MAX(b.Date) AS last_badge_date
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > DATE '2022-01-01'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) + COUNT(DISTINCT a.Id) > 5
),
AggregatedPostHistory AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS last_title_edit_date,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN ph.RevisionGUID ELSE NULL END) AS body_edit_revisions
    FROM PostHistory ph
    WHERE ph.CreationDate > DATE '2023-06-01'
    GROUP BY ph.PostId
)
SELECT
    pd.PostId,
    pd.PostTypeName,
    pd.OwnerDisplayName,
    pd.PostCreationDate,
    pd.Score,
    pd.ViewCount,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.is_closed_flag,
    pd.CleanedTitle,
    pd.comment_keyword_count,
    pd.post_category,
    ua.UserDisplayName AS ActiveUserName,
    ua.question_count,
    ua.total_question_score,
    ua.answer_count,
    ua.total_answer_score,
    ua.last_badge_date,
    aph.last_title_edit_date,
    aph.body_edit_revisions,
    CASE
        WHEN pd.Score > COALESCE(ua.total_answer_score, 0) THEN 'OwnerScoreHigher'
        WHEN pd.Score < COALESCE(ua.total_answer_score, 0) THEN 'UserScoreHigher'
        ELSE 'EqualScore'
    END AS score_comparison_with_user_answers,
    COALESCE(pd.CleanedTitle, 'No Title Provided') AS TitleOrPlaceholder,
    rp.cumulative_score,
    rp.previous_score,
    rp.dr_global_viewcount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pd.PostId AND pl.LinkTypeId = 3) AS duplicate_link_count
FROM PostDetails pd
JOIN RankedPosts rp ON pd.PostId = rp.PostId
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN AggregatedPostHistory aph ON pd.PostId = aph.PostId
WHERE pd.Score > 0 OR pd.ViewCount > 500

UNION ALL

SELECT
    NULL AS PostId,
    'Summary' AS PostTypeName,
    NULL AS OwnerDisplayName,
    NULL AS PostCreationDate,
    AVG(pd.Score) AS Score,
    AVG(pd.ViewCount) AS ViewCount,
    AVG(pd.AnswerCount) AS AnswerCount,
    AVG(pd.CommentCount) AS CommentCount,
    AVG(pd.FavoriteCount) AS FavoriteCount,
    CAST(SUM(pd.is_closed_flag) AS DECIMAL) / COUNT(pd.PostId) AS is_closed_flag,
    NULL AS CleanedTitle,
    NULL AS comment_keyword_count,
    NULL AS post_category,
    NULL AS ActiveUserName,
    NULL AS question_count,
    NULL AS total_question_score,
    NULL AS answer_count,
    NULL AS total_answer_score,
    NULL AS last_badge_date,
    NULL AS last_title_edit_date,
    NULL AS body_edit_revisions,
    NULL AS score_comparison_with_user_answers,
    NULL AS TitleOrPlaceholder,
    NULL AS cumulative_score,
    NULL AS previous_score,
    NULL AS dr_global_viewcount,
    NULL AS duplicate_link_count
FROM PostDetails pd
WHERE pd.PostTypeName = 'Question';