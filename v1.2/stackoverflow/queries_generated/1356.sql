-- {"query": "1356.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1351} 

WITH RECURSIVE TagHierarchy AS (
    SELECT t.Id, t.TagName, 0 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT child.Id, child.TagName, parent.Level + 1
    FROM Tags child
    JOIN Tags parent ON parent.Id = child.Id - 1 -- artificial hierarchy sequence as example
    WHERE child.IsModeratorOnly = 0 AND child.Id > parent.Id
),
LatestPostEdits AS (
    SELECT ph.PostId,
           MAX(ph.CreationDate) AS LastEditDate,
           MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.UserId END) AS LastEditorUserId
    FROM PostHistory ph
    GROUP BY ph.PostId
),
TopAnswerers AS (
    SELECT p.OwnerUserId, u.DisplayName, SUM(p.Score) AS TotalAnswerScore,
           ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC) AS rn
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, u.DisplayName
    HAVING SUM(p.Score) > 100
),
QuestionDetails AS (
    SELECT q.Id AS QuestionId,
           q.Title,
           q.CreationDate,
           q.Score,
           q.ViewCount,
           q.AnswerCount,
           q.Tags,
           COALESCE(td.Body, '') AS InitialBody,
           COALESCE(le.LastEditDate, q.LastEditDate) AS LastModified,
           u.DisplayName AS QuestionOwner,
           COALESCE(av.UpVotes, 0) AS UpVotes,
           COALESCE(av.DownVotes, 0) AS DownVotes,
           CASE 
                WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
                WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
                ELSE 'Open'
           END AS Status
    FROM Posts q
    LEFT JOIN PostHistory td ON td.PostId = q.Id AND td.PostHistoryTypeId = 2
    LEFT JOIN LatestPostEdits le ON le.PostId = q.Id
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN (
        SELECT p.PostTypeId, v.PostId,
               SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        JOIN Posts p ON p.Id = v.PostId
        WHERE p.PostTypeId IN (1,2)
        GROUP BY v.PostId, p.PostTypeId
    ) av ON av.PostId = q.Id
    WHERE q.PostTypeId = 1
),
FilteredAnswers AS (
    SELECT a.Id AS AnswerId,
           a.ParentId AS QuestionId,
           a.Score,
           a.CreationDate,
           a.OwnerUserId,
           CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
),
AnswerRanks AS (
    SELECT *,
           RANK() OVER (PARTITION BY QuestionId ORDER BY Score DESC, CreationDate ASC) AS AnswerRank
    FROM FilteredAnswers
),
UserBadgesAggregate AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    qd.QuestionId,
    qd.Title,
    qd.Status,
    qd.CreationDate,
    qd.LastModified,
    qd.Score AS QuestionScore,
    qd.ViewCount,
    qd.AnswerCount,
    qd.QuestionOwner,
    qd.UpVotes,
    qd.DownVotes,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ta.DisplayName AS TopAnswerer,
    ta.TotalAnswerScore,
    ar.AnswerId,
    ar.Score AS AnswerScore,
    ar.IsAccepted,
    ar.AnswerRank,
    ARRAY_AGG(DISTINCT th.TagName) FILTER (WHERE th.Level <= 2 AND POSITION('<' || th.TagName || '>' IN qd.Tags) > 0) AS TopLevelTags,
    CASE 
        WHEN LENGTH(qd.InitialBody) > 100 THEN LEFT(qd.InitialBody, 100) || '...'
        ELSE qd.InitialBody
    END AS SnippetInitialBody,
    COALESCE(qd.AnalyzedSentiment, 'Neutral') AS SentimentAnalysis, -- pretend computed elsewhere
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostLinks pl WHERE pl.PostId = qd.QuestionId AND pl.LinkTypeId = 3
        ) THEN 'Has Duplicates'
        ELSE 'No Duplicates'
    END AS DuplicateStatus
FROM QuestionDetails qd
LEFT JOIN AnswerRanks ar ON ar.QuestionId = qd.QuestionId AND ar.AnswerRank <= 3
LEFT JOIN TopAnswerers ta ON ta.UserId = ar.OwnerUserId
LEFT JOIN UserBadgesAggregate ua ON ua.UserId = qd.OwnerUserId
LEFT JOIN TagHierarchy th ON POSITION('<' || th.TagName || '>' IN qd.Tags) > 0
GROUP BY qd.QuestionId, qd.Title, qd.Status, qd.CreationDate, qd.LastModified, qd.Score, qd.ViewCount, qd.AnswerCount, qd.QuestionOwner, 
         qd.UpVotes, qd.DownVotes, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, ta.DisplayName, ta.TotalAnswerScore,
         ar.AnswerId, ar.Score, ar.IsAccepted, ar.AnswerRank, qd.InitialBody, qd.AnalyzedSentiment, qd.OwnerUserId;
