-- {"query": "54006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1176} 

WITH recent_questions AS (
    SELECT
        p.Id,
        p.Tags,
        p.CreationDate,
        u.Reputation AS UserReputation,
        u.Location,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCnt,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCnt,
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY
        p.Id, p.Tags, p.CreationDate,
        u.Reputation, u.Location,
        p.Score, p.ViewCount
),
tag_tokens AS (
    SELECT
        rq.Id,
        rq.Tags,
        rq.Score,
        rq.ViewCount,
        rq.CommentCount,
        rq.UpVoteCnt,
        rq.DownVoteCnt,
        rq.EditCount,
        regexp_split_to_table(rq.Tags, '<>|<>') AS TagName
    FROM recent_questions rq
    WHERE rq.Tags IS NOT NULL
),
tag_stats AS (
    SELECT
        TagName,
        COUNT(DISTINCT Id) AS QuestionCount,
        AVG(Score) AS AvgScore,
        AVG(ViewCount) AS AvgViews,
        SUM(CommentCount) AS TotalComments,
        SUM(UpVoteCnt) AS TotalUpVotes,
        SUM(DownVoteCnt) AS TotalDownVotes,
        SUM(EditCount) AS TotalEdits,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT Id) DESC) AS Rank
    FROM tag_tokens
    GROUP BY TagName
)
SELECT
    TagName,
    QuestionCount,
    AvgScore,
    AvgViews,
    TotalComments,
    TotalUpVotes,
    TotalDownVotes,
    TotalEdits,
    Rank
FROM tag_stats
WHERE Rank <= 10
ORDER BY QuestionCount DESC;
