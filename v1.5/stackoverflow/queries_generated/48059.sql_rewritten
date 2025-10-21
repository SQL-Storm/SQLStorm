-- {"query": "48059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 750} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN rp.PostTypeId = 1 THEN rp.Id END) AS QuestionCount,
        COUNT(CASE WHEN rp.PostTypeId = 2 THEN rp.Id END) AS AnswerCount,
        AVG(CASE WHEN rp.PostTypeId = 1 THEN rp.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN rp.PostTypeId = 2 THEN rp.Score ELSE NULL END) AS AvgAnswerScore,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN rp.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN rp.AnswerCount ELSE 0 END) AS TotalAnsweredAnswers
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id
),
PostVoteDetails AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id ELSE NULL END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id ELSE NULL END) AS DownVotes,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN v.Id ELSE NULL END) AS Favorites
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod', 'Favorite')
    GROUP BY p.Id
)
SELECT
    rp.Id AS PostId,
    rp.PostTypeId,
    pt.Name AS PostTypeName,
    rp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgQuestionScore,
    ups.AvgAnswerScore,
    ups.TotalQuestionViews,
    ups.TotalAnsweredAnswers,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount,
    rp.FavoriteCount AS PostFavoriteCount,
    rp.ClosedDate,
    pvd.UpVotes,
    pvd.DownVotes,
    pvd.Favorites AS PostLinkFavorites
FROM RankedPosts rp
JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN PostVoteDetails pvd ON rp.Id = pvd.PostId
WHERE rp.rn <= 5000 -- Limit to top 5000 most recent posts for benchmarking
ORDER BY rp.CreationDate DESC;