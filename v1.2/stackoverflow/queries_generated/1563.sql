-- {"query": "1563.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1297} 
WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(v.VoteWeight), 0) AS VoteSum,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            PostId,
            CASE 
                WHEN vt.Name = 'UpMod' THEN 1
                WHEN vt.Name = 'DownMod' THEN -1
                ELSE 0
            END AS VoteWeight
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    ) v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
), RecursiveTagCte (Id, TagName, ParentTag, Depth) AS (
    SELECT
        t.Id,
        t.TagName,
        NULL::varchar(35) AS ParentTag,
        1 AS Depth
    FROM Tags t
    WHERE t.Count > 1000 -- high frequency tags as roots

    UNION ALL

    SELECT
        tg.Id,
        tg.TagName,
        tr.TagName AS ParentTag,
        tr.Depth + 1 AS Depth
    FROM Tags tg
    JOIN RecursiveTagCte tr ON tg.TagName LIKE tr.TagName || '%'
    WHERE tg.Id <> tr.Id AND tr.Depth < 3
), AcceptedAnswerRank AS (
    SELECT
        p.Id AS QuestionId,
        p.AcceptedAnswerId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        RANK() OVER (PARTITION BY p.Id ORDER BY a.Score DESC) AS AnswerRank
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
), PostsWithHistory AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        piti.Name AS HistoryType,
        ph.CreationDate AS HistoryDate,
        ph.UserId As HistoryUserId,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS HistVersionDesc
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostHistoryTypes piti ON piti.Id = ph.PostHistoryTypeId
), CTE_CommentsAggregated AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCountForPost,
        MAX(c.Score) AS MaxCommentScore,
        STRING_AGG(SUBSTRING(c.Text,1,20) || '...', ' | ') AS SampleComments
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.VoteSum,
    ups.AvgPostScore,
    ups.LastPostDate,
    rng.FragmentedName,
    aar.AcceptedAnswerId,
    COALESCE(aans.AnswerHighestScore, 0) AS HighestAcceptedAnswerScore,
    phcut.HistoryType AS LatestPostHistoryType,
    phcut.HistVersionDesc,
    ca.CommentCountForPost,
    ca.MaxCommentScore,
    ca.SampleComments,
    ts.SumTagsSeen,
    ts.TagSelector
FROM UserPostStats ups
LEFT JOIN (
    SELECT
        u.Id AS UserId,
        STRING_AGG(CASE WHEN t.Id IS NOT NULL THEN '✔' ELSE '𐄂' END, '') AS TagSelector,
        COUNT(t.Id) AS SumTagsSeen,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS FragmentedName
    FROM Users u
    CROSS JOIN LATERAL (
        SELECT tg.Id, tg.TagName
        FROM Tags tg
        JOIN Posts p ON p.OwnerUserId = u.Id
        WHERE p.PostTypeId = 1 AND p.Tags LIKE CONCAT('%<' , tg.TagName , '>%')
        LIMIT 10
    ) t ON true
    GROUP BY u.Id
) ts ON ts.UserId = ups.UserId
LEFT JOIN AcceptedAnswerRank aar ON aar.AcceptedAnswerId IS NOT NULL 
                                AND aar.AnswerId = aar.AcceptedAnswerId 
                                AND aar.QuestionId IN (
                                    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ups.UserId
                                )
LEFT JOIN (
    SELECT 
        a.ParentId AS QuestionId,
        MAX(a.Score) AS AnswerHighestScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
) aans ON aans.QuestionId = aar.QuestionId
LEFT JOIN (
    SELECT
        HistoryCut.*
    FROM (
        SELECT DISTINCT ON (p.Id)
            p.Id,
            p.OwnerUserId,
            Apoth.HistoryType,
            Apoth.HistVersionDesc
        FROM Posts p
        JOIN PostsWithHistory Apoth ON Apoth.Id = p.Id
        WHERE Apoth.HistVersionDesc = 1
        ORDER BY p.Id, Apoth.HistVersionDesc
     ) HistoryCut
) phcut ON phcut.OwnerUserId = ups.UserId
LEFT JOIN CTE_CommentsAggregated ca ON ca.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ups.UserId)
WHERE ups.TotalPosts > 5 
  AND (ups.VoteSum > 50 OR ups.AvgPostScore > 5)
ORDER BY ups.VoteSum DESC NULLS LAST, ups.AvgPostScore DESC
LIMIT 100;