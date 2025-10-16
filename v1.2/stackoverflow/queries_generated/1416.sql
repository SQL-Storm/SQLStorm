-- {"query": "1416.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1515} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id, 
        t.TagName, 
        COALESCE(t.ExcerptPostId, 0) AS ExcerptPostId, 
        COALESCE(t.WikiPostId, 0) AS WikiPostId, 
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        COALESCE(child.ExcerptPostId, 0),
        COALESCE(child.WikiPostId, 0),
        rh.Level + 1
    FROM Tags child
    JOIN RecursiveTagHierarchy rh ON child.Id > rh.Id AND child.IsRequired = 0
    WHERE rh.Level < 3
), PostDetails AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.Id AS UserId, u.DisplayName, u.Reputation, u.Location,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) rn
    FROM 
        Posts p 
        LEFT JOIN Users u ON p.OwnerUserId = u.Id 
    WHERE p.PostTypeId IN (1, 2)  -- Question or Answer
), TopQuestions AS (
    SELECT pd.PostId, pd.Title, pd.ViewCount, pd.Score, u.DisplayName AS OwnerName, OwnerReputation
    FROM PostDetails pd
    LEFT JOIN (
        SELECT UserId, MAX(Reputation) AS OwnerReputation FROM Users GROUP BY UserId
    ) u ON pd.OwnerUserId = u.UserId
    WHERE pd.PostTypeId = 1
    AND pd.ViewCount > 1000 -- popular questions
), InvalidLinks AS (
    SELECT pl.Id, pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName
    FROM PostLinks pl
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts p1 ON pl.PostId = p1.Id
    LEFT JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE p1.PostTypeId IS NULL OR p2.PostTypeId IS NULL
), BadgesWithUserAvgReputation AS (
    SELECT
      b.Id, b.UserId, b.Name AS BadgeName, b.Date,
      (SELECT AVG(Reputation) FROM Users WHERE Reputation IS NOT NULL) AS AvgUserReputation,
      u.Reputation AS UserReputation,
      CASE 
         WHEN u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation IS NOT NULL) THEN 'Above Average'
         ELSE 'Below Average or Null' 
      END as RepComparison
    FROM Badges b
    LEFT JOIN Users u ON b.UserId = u.Id
    WHERE b.Class = 1 -- Gold badges for example
), PostVoteAgg AS (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
           MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
), RecentActivityWindow AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.Tags,
        ph.CreationDate AS LastPostHistoryChange,
        MAX(COALESCE(v.CreationDate, p.CreationDate)) OVER (PARTITION BY p.Id) AS MostRecentActivityDate,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) rn
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '180 DAY'
), DuplicateQuestionMatches AS (
    SELECT pl.PostId AS DuplicateQuestionId, pl.RelatedPostId AS OriginalQuestionId, pl.CreationDate AS LinkCreated
    FROM PostLinks pl 
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
      AND EXISTS (SELECT 1 FROM Posts pq WHERE pq.Id = pl.PostId AND pq.PostTypeId = 1)
      AND EXISTS (SELECT 1 FROM Posts pq2 WHERE pq2.Id = pl.RelatedPostId AND pq2.PostTypeId = 1)
)
SELECT
    dq.DuplicateQuestionId, dq.OriginalQuestionId,
    q.Title AS DuplicateTitle,
    oq.Title AS OriginalTitle,
    q.ViewCount AS DuplicateViewCount,
    oq.ViewCount AS OriginalViewCount,
    q.Score AS DuplicateScore,
    oq.Score AS OriginalScore,
    b.BadgeName,
    b.UserReputation,
    b.AvgUserReputation,
    b.RepComparison,
    COALESCE(pv.UpVotes, 0) AS UpVotes,
    COALESCE(pv.DownVotes, 0) AS DownVotes,
    ra.MostRecentActivityDate,
    pt.Name AS PostType,
    st.Name AS PostHistoryChangeType,
    CASE 
        WHEN COALESCE(vt.Name, 'NoVote') = 'UpMod' THEN 'Positive vote'
        WHEN COALESCE(vt.Name, 'NoVote') = 'DownMod' THEN 'Negative vote'
        ELSE 'No vote or other'
    END AS VoteEffect,
    adj.ActivityDescription
FROM DuplicateQuestionMatches dq
INNER JOIN Posts q ON dq.DuplicateQuestionId = q.Id
INNER JOIN Posts oq ON dq.OriginalQuestionId = oq.Id
LEFT JOIN BadgesWithUserAvgReputation b ON b.UserId = q.OwnerUserId
LEFT JOIN PostVoteAgg pv ON pv.PostId = q.Id
LEFT JOIN RecentActivityWindow ra ON ra.PostId = q.Id
LEFT JOIN PostTypes pt ON pt.Id = q.PostTypeId
LEFT JOIN (
    SELECT ph1.PostId, ph1.PostHistoryTypeId, pht.Name AS HistoryName,
           CASE
             WHEN ph1.PostHistoryTypeId IN (10, 11, 12) THEN '(' || trim(ph1.Comment) || ')'
             ELSE ''
           END AS ActivityDescription,
           ROW_NUMBER() OVER (PARTITION BY ph1.PostId ORDER BY ph1.CreationDate DESC) as rn
    FROM PostHistory ph1
    LEFT JOIN PostHistoryTypes pht ON ph1.PostHistoryTypeId = pht.Id
) st ON st.PostId = q.Id AND st.rn = 1
LEFT JOIN Votes v ON v.PostId = q.Id AND v.CreationDate = (
    SELECT MAX(CreationDate) FROM Votes WHERE PostId = q.Id
)
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
ORDER BY dq.DuplicateQuestionId
LIMIT 50;
