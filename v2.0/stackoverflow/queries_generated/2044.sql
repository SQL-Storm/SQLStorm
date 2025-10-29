-- {"query": "2044.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1303} 

with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) as QuestionAnswerCount,
        coalesce(p.ViewCount, 0) as QuestionViewCount,
        coalesce(sum(v.VoteTypeCount), 0) as TotalVotes,
        count(distinct p.Id) as QuestionCount
    from Tags t
    left join Posts p on p.PostTypeId = 1 and 
        ('<' || t.TagName || '>') = any(string_to_array(p.Tags, '>')::text[])
    left join (
        select PostId, VoteTypeId, count(*) as VoteTypeCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod, DownMod
        group by PostId, VoteTypeId
    ) v on v.PostId = p.Id
    group by t.Id, t.TagName, p.AnswerCount, p.ViewCount
),
UserBadgeActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        b.TagBased,
        count(*) as BadgeCount,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class, b.TagBased
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        row_number() over (
            partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last
        ) as RankInType
    from Posts p
),
ComplexUserStats as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesGiven,
        avg(ph.PostHistoryCount) as AvgPostEdits,
        first_value(b.Name) over (partition by u.Id order by b.Date desc nulls last) as LatestBadgeName,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join (
        select PostId, count(*) as PostHistoryCount
        from PostHistory
        group by PostId
    ) ph on ph.PostId = p.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
ClosedQuestions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        ph.Text as CloseReasonJson,
        crt.Name as CloseReason,
        row_number() over (partition by crt.Name order by p.CreationDate desc) as RecentRank
    from Posts p
    inner join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
DuplicateQuestions as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsInLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
MergedClosedAndDuplicate as (
    select
        cq.Id as QuestionId,
        cq.Title as ClosedTitle,
        coalesce(cq.CloseReason, 'Unknown') as CloseReason,
        dq.RelatedPostId as DuplicateOf,
        dq.DuplicateTitle,
        cq.CreationDate as CloseDate
    from ClosedQuestions cq
    left join DuplicateQuestions dq on dq.PostId = cq.Id
    where cq.RecentRank <= 5
)
select 
    t.TagName,
    t.QuestionCount,
    t.TotalVotes,
    t.QuestionAnswerCount,
    t.QuestionViewCount,
    u.Id as UserId,
    u.DisplayName,
    u.QuestionCount,
    u.AnswerCount,
    u.UpVotesGiven,
    u.DownVotesGiven,
    u.AvgPostEdits,
    u.LatestBadgeName,
    u.LastVoteDate,
    m.CloseReason,
    m.DuplicateOf,
    m.DuplicateTitle,
    m.CloseDate,
    ua.PostsInLast30Days
from RecursiveTagCounts t
cross join lateral (
    select *
    from ComplexUserStats u
    order by u.QuestionCount desc nulls last
    limit 1
) u
left join MergedClosedAndDuplicate m on m.QuestionId = (
    select Id from Posts p2
    where p2.Tags like '%' || t.TagName || '%'
    and p2.PostTypeId = 1
    order by p2.Score desc nulls last
    limit 1
)
left join UserActivityWindow ua on ua.Id = u.Id
where t.QuestionCount > 10
order by t.TotalVotes desc nulls last, u.QuestionCount desc nulls last
limit 25;
