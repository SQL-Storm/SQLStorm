WITH 
    /* Per-question vote aggregates */
    question_votes AS (
        SELECT
            p.Id AS PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY p.Id
    ),
    /* Count edits per question (edit body only) */
    question_edits AS (
        SELECT
            ph.PostId,
            COUNT(*) AS EditCount
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 5          -- Edit Body
        GROUP BY ph.PostId
    ),
    /* Split tags into rows */
    tag_split AS (
        SELECT
            p.Id AS PostId,
            TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '<><>'))) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    /* Aggregate stats per user‑tag combination */
    user_tag_stats AS (
        SELECT
            u.Id          AS UserId,
            u.DisplayName,
            ts.Tag,
            COUNT(*)                     AS QuestionCount,
            SUM(p.Score)                 AS TotalScore,
            SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedCount,
            SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedCount,
            AVG(COALESCE(qv.UpVotes, 0))   AS AvgUpVotes,
            AVG(COALESCE(qv.DownVotes, 0)) AS AvgDownVotes,
            AVG(COALESCE(qv.AcceptedVotes, 0)) AS AvgAcceptedVotes,
            SUM(COALESCE(qe.EditCount, 0)) AS TotalEdits
        FROM Users u
        JOIN Posts p
            ON p.OwnerUserId = u.Id
           AND p.PostTypeId = 1
        JOIN tag_split ts
            ON ts.PostId = p.Id
        LEFT JOIN question_votes qv
            ON qv.PostId = p.Id
        LEFT JOIN question_edits qe
            ON qe.PostId = p.Id
        GROUP BY u.Id, u.DisplayName, ts.Tag
    ),
    /* Rank tags within each user */
    ranked_user_tags AS (
        SELECT
            UserId,
            DisplayName,
            Tag,
            QuestionCount,
            TotalScore,
            AcceptedCount,
            ClosedCount,
            AvgUpVotes,
            AvgDownVotes,
            AvgAcceptedVotes,
            TotalEdits,
            RANK() OVER (PARTITION BY UserId
                         ORDER BY QuestionCount DESC, TotalScore DESC) AS TagRank
        FROM user_tag_stats
    )
SELECT
    UserId,
    DisplayName,
    Tag,
    QuestionCount,
    TotalScore,
    AcceptedCount,
    ClosedCount,
    AvgUpVotes,
    AvgDownVotes,
    AvgAcceptedVotes,
    TotalEdits,
    TagRank
FROM ranked_user_tags
WHERE TagRank <= 5
ORDER BY UserId, TagRank;