WITH RECURSIVE
    question_votes AS (
        SELECT
            p.Id AS PostId,
            COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
            COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
            COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) AS AcceptedVotes
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY p.Id
    ),
    question_edits AS (
        SELECT
            ph.PostId,
            COUNT(*) AS EditCount
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 5
        GROUP BY ph.PostId
    ),
    tag_split AS (
        SELECT
            p.Id AS PostId,
            CASE
                WHEN LENGTH(p.Tags) >= 2 AND POSITION('>' IN p.Tags) > 0
                THEN SUBSTRING(p.Tags FROM 2 FOR POSITION('>' IN p.Tags)-2)
                WHEN LENGTH(p.Tags) >= 2
                THEN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2)
                ELSE NULL
            END AS Tag,
            CASE WHEN POSITION('><' IN p.Tags) > 0 THEN SUBSTRING(p.Tags FROM POSITION('><' IN p.Tags)+2) ELSE NULL END AS rest
        FROM Posts p
        WHERE p.PostTypeId = 1
        UNION ALL
        SELECT
            ts.PostId,
            CASE
                WHEN ts.rest IS NOT NULL AND POSITION('><' IN ts.rest) > 0
                THEN SUBSTRING(ts.rest FROM 1 FOR POSITION('><' IN ts.rest)-1)
                WHEN ts.rest IS NOT NULL
                THEN ts.rest
                ELSE NULL
            END AS Tag,
            CASE WHEN ts.rest IS NOT NULL AND POSITION('><' IN ts.rest) > 0 THEN SUBSTRING(ts.rest FROM POSITION('><' IN ts.rest)+2) ELSE NULL END AS rest
        FROM tag_split ts
        WHERE ts.rest IS NOT NULL AND ts.rest <> ''
    ),
    user_tag_stats AS (
        SELECT
            u.Id          AS UserId,
            u.DisplayName,
            ts.Tag,
            COUNT(*)                     AS QuestionCount,
            SUM(p.Score)                 AS TotalScore,
            SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedCount,
            SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedCount,
            AVG(qv.UpVotes)               AS AvgUpVotes,
            AVG(qv.DownVotes)             AS AvgDownVotes,
            AVG(qv.AcceptedVotes)         AS AvgAcceptedVotes,
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