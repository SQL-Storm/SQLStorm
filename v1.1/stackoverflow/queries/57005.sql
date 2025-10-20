-- {"query": "57005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 969} 
WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Posts a ON p.Id = a.ParentId
    WHERE
        u.Reputation > 1000
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    ORDER BY
        UpVoteCount DESC, DownVoteCount ASC, AnswerCount DESC
    LIMIT 10
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        SUM(v.BountyAmount) AS TotalBounty,
        AVG(p.Score) AS AverageScore
    FROM
        Tags t
    JOIN
        Posts p ON t.Id = p.Id
    JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
    HAVING
        COUNT(p.Id) > 50
    ORDER BY
        TotalBounty DESC, AverageScore DESC
    LIMIT 10
),
ComplexPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.ViewCount,
        p.AnswerCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT v.UserId) AS VoterCount,
        SUM(v.BountyAmount) AS TotalBounty,
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId = 1 AND p.AnswerCount > 10
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.ViewCount, p.AnswerCount
    ORDER BY
        ViewCount DESC, AnswerCount DESC, CommentCount DESC
    LIMIT 10
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.AnswerCount,
    tu.UpVoteCount,
    tu.DownVoteCount,
    ts.TagName,
    ts.QuestionCount,
    ts.UniqueVoters,
    ts.TotalBounty AS TagTotalBounty,
    ts.AverageScore,
    cp.PostId,
    cp.Title AS PostTitle,
    cp.CreationDate,
    cp.ViewCount,
    cp.AnswerCount,
    cp.CommentCount,
    cp.VoterCount,
    cp.TotalBounty AS PostTotalBounty,
    cp.EditCount
FROM
    TopUsers tu
CROSS JOIN
    TagStats ts
LEFT JOIN
    ComplexPosts cp ON tu.UserId = cp.OwnerUserId
ORDER BY
    tu.UpVoteCount DESC, cp.ViewCount DESC;