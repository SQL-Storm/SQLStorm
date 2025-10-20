-- {"query": "3020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1114} 
WITH PostAnswerCounts AS (
    SELECT
        p.PostTypeId,
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CloseDate,
        p.ContentLicense,
        COALESCE(pc.AnswerSum, 0) AS TotalAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RowNum
    FROM
        Posts p
    LEFT JOIN (
        SELECT
            ParentId,
            SUM(Score) AS AnswerSum
        FROM
            Posts
        WHERE
            PostTypeId = 2
        GROUP BY
            ParentId
    ) pc ON p.Id = pc.ParentId
),
RecentQuestions AS (
    SELECT
        p1.PostTypeId,
        p1.Id AS QuestionId,
        p1.Title,
        p1.CreationDate,
        p1.OwnerUserId,
        p1.Tags,
        p1.Score,
        p1.ViewCount,
        p1.AnswerCount,
        p1.CommentCount,
        p1.FavoriteCount,
        p1.CloseDate,
        p1.ContentLicense,
        p2.PostId AS AcceptedAnswerId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        u.LastAccessDate,
        ARRAY_REMOVE(STRING_TO_ARRAY(p1.Tags, '><'), '') AS TagList
    FROM
        Posts p1
    LEFT OUTER JOIN
        Posts p2 ON p1.AcceptedAnswerId = p2.Id
    INNER JOIN
        Users u ON p1.OwnerUserId = u.Id
    WHERE
        p1.PostTypeId = 1
        AND p1.CreationDate > CURRENT_TIMESTAMP - INTERVAL '180 days'
        AND p1.AnswerCount > 0
        AND p1.Score >= 5
),
AggregatedTags AS (
    SELECT
        unnest(TagList) AS Tag,
        COUNT(*) FILTER (WHERE Tag IS NOT NULL) AS TagFrequency
    FROM
        RecentQuestions
    GROUP BY
        Tag
),
TopTags AS (
    SELECT
        Tag,
        TagFrequency,
        RANK() OVER (ORDER BY TagFrequency DESC) AS TagRank
    FROM
        AggregatedTags
    WHERE
        Tag IS NOT NULL
),
UserAnswerStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT a.PostId) AS AnswerCount,
        SUM(a.PostScore) AS TotalAnswerScore,
        AVG(a.PostScore) AS AvgAnswerScore,
        MAX(a.PostScore) AS MaxAnswerScore
    FROM
        Users u
    LEFT JOIN (
        SELECT
            p.Id AS PostId,
            p.OwnerUserId,
            p.Score AS PostScore
        FROM
            Posts p
        WHERE
            p.PostTypeId = 2
    ) a ON u.Id = a.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName
),
VotesAnalysis AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        COUNT(*) AS VoteCount,
        COUNT(DISTINCT v.UserId) AS Voters
    FROM
        Votes v
    GROUP BY
        v.PostId, v.VoteTypeId
)
SELECT
    pq.PostId AS QuestionID,
    pq.Title AS QuestionTitle,
    pq.CreationDate AS QuestionCreated,
    pq.OwnerDisplayName AS QuestionOwner,
    pq.Reputation AS OwnerReputation,
    pq.TotalAnswerScore,
    qr.AcceptedAnswerId,
    qa.PostScore AS AcceptedAnswerScore,
    qa.CreationDate AS AnswerCreated,
    qa.OwnerDisplayName AS AnswerOwner,
    ua.AnswerCount,
    ua.TotalAnswerScore AS OwnerTotalAnswerScore,
    ua.AvgAnswerScore,
    ua.MaxAnswerScore,
    tg.Tag,
    tg.TagFrequency,
    t.TagRank,
    v1.VoteCount AS UpvoteCount,
    v2.VoteCount AS DownvoteCount,
    v1.Voters AS Upvoters,
    v2.Voters AS Downvoters
FROM
    RecentQuestions pq
JOIN
    PostAnswerCounts qa ON pq.AcceptedAnswerId = qa.PostId
LEFT JOIN
    UserAnswerStats ua ON pq.OwnerUserId = ua.UserId
LEFT JOIN
    TopTags t ON t.Tag = ANY(ARRAY(SELECT unnest(STRING_TO_ARRAY(pq.Tags, '><'))))
LEFT JOIN
    VotesAnalysis v1 ON pq.PostId = v1.PostId AND v1.VoteTypeId = 2
LEFT JOIN
    VotesAnalysis v2 ON pq.PostId = v2.PostId AND v2.VoteTypeId = 3
LEFT JOIN
    (SELECT PostId, SUM(VoteCount) AS VoteCount, COUNT(DISTINCT UserId) AS Voters
     FROM Votes
     WHERE VoteTypeId IN (2,3)
     GROUP BY PostId) v ON pq.PostId = v.PostId
WHERE
    pq.RowNum = 1
ORDER BY
    pq.CreationDate DESC
LIMIT 100;