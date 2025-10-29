-- {"query": "4478.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1410} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.UserDisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) OVER (PARTITION BY ph.PostId) as body_edit_count
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 24)
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS total_posts_owned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
        AVG(p.Score) AS avg_post_score,
        MAX(p.CreationDate) AS last_post_date
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
PostEditImpact AS (
    SELECT
        rpe.PostId,
        rpe.UserId AS editorUserId,
        rpe.UserDisplayName AS editorDisplayName,
        rpe.EditDate,
        rpe.body_edit_count,
        p.OwnerUserId AS originalOwnerUserId,
        p.Score AS originalPostScore,
        p.ViewCount AS originalPostViewCount,
        p.AnswerCount AS originalAnswerCount,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS post_type_name,
        p.Title,
        p.Tags,
        p.Score - COALESCE((SELECT SUM(Score) FROM Comments WHERE PostId = p.Id), 0) AS net_score,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed
    FROM RankedPostEdits rpe
    JOIN Posts p ON rpe.PostId = p.Id
    WHERE rpe.rn = 1 AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserReputationChange AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        LAG(u.Reputation, 1, u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate) AS previous_reputation,
        u.CreationDate,
        u.LastAccessDate,
        p.Id AS post_id,
        p.Title AS post_title,
        p.PostTypeId,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS post_type_name
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    WHERE u.DisplayName IS NOT NULL AND LENGTH(u.DisplayName) > 0
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    pei.post_id,
    pei.Title,
    pei.post_type_name,
    pei.Tags,
    pei.editorUserId,
    pei.editorDisplayName,
    pei.EditDate,
    pei.body_edit_count,
    pei.originalPostScore,
    pei.originalPostViewCount,
    pei.originalAnswerCount,
    pei.net_score,
    pei.is_closed,
    COALESCE(upa.total_posts_owned, 0) AS editor_total_posts_owned,
    COALESCE(upa.question_count, 0) AS editor_questions_owned,
    COALESCE(upa.answer_count, 0) AS editor_answers_owned,
    COALESCE(upa.avg_post_score, 0.0) AS editor_avg_post_score,
    COALESCE(ub.gold_badges, 0) AS editor_gold_badges,
    COALESCE(ub.silver_badges, 0) AS editor_silver_badges,
    COALESCE(ub.bronze_badges, 0) AS editor_bronze_badges,
    urc.Reputation AS editor_current_reputation,
    urc.previous_reputation AS editor_previous_reputation,
    (urc.Reputation - urc.previous_reputation) AS reputation_change_since_last_access,
    pht.Name AS last_edit_type
FROM PostEditImpact pei
LEFT JOIN UserPostActivity upa ON pei.editorUserId = upa.OwnerUserId
LEFT JOIN UserBadges ub ON pei.editorUserId = ub.UserId
LEFT JOIN UserReputationChange urc ON pei.editorUserId = urc.UserId AND pei.EditDate BETWEEN urc.CreationDate AND urc.LastAccessDate
LEFT JOIN PostHistoryTypes pht ON pei.PostHistoryTypeId = pht.Id
WHERE pei.originalOwnerUserId <> pei.editorUserId
AND pei.EditorDisplayName IS NOT NULL
AND LOWER(pei.Tags) LIKE '%<sql>%'
AND pei.EditDate > DATE('now', '-1 year')
ORDER BY pei.EditDate DESC
LIMIT 1000;
