-- {"query": "328.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1392} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(v.VoteCount) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUserBadges as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as BadgeRank
    from Badges b
    join RecursiveUserActivity r on r.UserId = b.UserId
    where b.Date > (current_date - interval '1 year')
),
PostWithLinkInfo as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        rp.Score as RelatedPostScore,
        rp.PostTypeId as RelatedPostTypeId
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts rp on rp.Id = pl.RelatedPostId
    where p.PostTypeId in (1,2)
),
RankedPosts as (
    select
        p.*,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank,
        dense_rank() over (partition by p.OwnerUserId order by p.PostTypeId) as PostTypeRank
    from PostWithLinkInfo p
),
QuestionCloseStats as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotes,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenVotes,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenDate,
        string_agg(distinct crt.Name, ', ') filter (where ph.PostHistoryTypeId = 10) as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
UserActivitySummary as (
    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.QuestionCount,
        r.AnswerCount,
        r.CommentCount,
        r.TotalVotesReceived,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as ActiveQuestions,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as ActiveAnswers,
        coalesce(sum(case when p.Score > 10 then 1 else 0 end),0) as HighlyScoredPosts,
        count(distinct b.Id) as RecentBadges
    from RecursiveUserActivity r
    left join Posts p on p.OwnerUserId = r.UserId and p.CreationDate > (current_date - interval '6 months')
    left join Badges b on b.UserId = r.UserId and b.Date > (current_date - interval '6 months')
    group by r.UserId, r.DisplayName, r.Reputation, r.QuestionCount, r.AnswerCount, r.CommentCount, r.TotalVotesReceived
)
select
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.TotalVotesReceived,
    uas.ActiveQuestions,
    uas.ActiveAnswers,
    uas.HighlyScoredPosts,
    uas.RecentBadges,
    array_agg(distinct tb.BadgeName order by tb.Class, tb.BadgeName) filter (where tb.BadgeRank <= 3) as TopBadges,
    jsonb_agg(jsonb_build_object(
        'PostId', rp.Id,
        'PostType', rp.PostTypeId,
        'Score', rp.Score,
        'ViewCount', rp.ViewCount,
        'LinkType', rp.LinkTypeName,
        'RelatedPostScore', rp.RelatedPostScore,
        'RelatedPostType', rp.RelatedPostTypeId
    ) order by rp.Score desc nulls last) as PostsWithLinks,
    qc.CloseVotes,
    qc.ReopenVotes,
    qc.LastCloseDate,
    qc.LastReopenDate,
    qc.CloseReasons
from UserActivitySummary uas
left join TopUserBadges tb on tb.UserId = uas.UserId
left join RankedPosts rp on rp.OwnerUserId = uas.UserId and rp.PostRank <= 5
left join QuestionCloseStats qc on qc.PostId = rp.Id and rp.PostTypeId = 1
where uas.Reputation > 5000
group by
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.TotalVotesReceived,
    uas.ActiveQuestions,
    uas.ActiveAnswers,
    uas.HighlyScoredPosts,
    uas.RecentBadges,
    qc.CloseVotes,
    qc.ReopenVotes,
    qc.LastCloseDate,
    qc.LastReopenDate,
    qc.CloseReasons
order by uas.Reputation desc, uas.UserId
limit 50;