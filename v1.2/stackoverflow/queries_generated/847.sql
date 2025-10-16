-- {"query": "847.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1381} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Class

    union all

    select
        ubc.UserId,
        ubc.DisplayName,
        ubc.Class,
        ubc.BadgeCount
    from UserBadgeCounts ubc
    where ubc.BadgeCount > 0
),
TopUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(SUM(vt.VoteCount),0) as TotalVotesReceived,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        row_number() over (order by u.Reputation desc, TotalVotesReceived desc) as Rank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select v.PostId, count(*) as VoteCount
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        where vt.Name in ('UpMod', 'AcceptedByOriginator')
        group by v.PostId
    ) vt on vt.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having u.Reputation > 1000
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.AnswerCount,
        array_agg(distinct coalesce(t.TagName, '')) as Tags,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        u.DisplayName as OwnerName,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join LATERAL (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as TagName
    ) t on true
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.ViewCount, p.Score, p.CreationDate, p.AnswerCount, p.ClosedDate, u.DisplayName
),
AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
ClosedReasonsCount as (
    select
        p.Id as PostId,
        crt.Name as CloseReason,
        count(*) as CloseVoteCount
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    group by p.Id, crt.Name
),
UserActivityWindow as (
    select 
        u.Id,
        u.DisplayName,
        p.PostTypeId,
        count(p.Id) over (partition by u.Id order by p.CreationDate rows between 6 preceding and current row) as PostsLast7Days,
        count(c.Id) over (partition by u.Id order by c.CreationDate rows between 6 preceding and current row) as CommentsLast7Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    where p.CreationDate >= current_date - interval '30 days' or c.CreationDate >= current_date - interval '30 days'
),
HighActivityUsers as (
    select distinct
        Id,
        DisplayName
    from UserActivityWindow
    where PostsLast7Days > 10 or CommentsLast7Days > 20
)
select
    tu.Rank,
    tu.DisplayName as User,
    tu.Reputation,
    tu.TotalVotesReceived,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.CommentCount,
    tu.MaxAnswerScore,
    tu.MaxQuestionScore,
    qa.QuestionId,
    qa.Title as QuestionTitle,
    qa.Score as QuestionScore,
    qa.ViewCount as QuestionViews,
    array_to_string(qa.Tags, ', ') as QuestionTags,
    qa.IsClosed,
    qa.OwnerName as QuestionOwner,
    qa.CommentCount as QuestionComments,
    qa.UpVotes as QuestionUpVotes,
    qa.DownVotes as QuestionDownVotes,
    ar.AnswerId,
    ar.Score as AnswerScore,
    ar.AnswerRank,
    dr.RelatedPostId as DuplicateOf,
    cr.CloseReason,
    cr.CloseVoteCount,
    hu.DisplayName as HighActivityUser
from TopUsers tu
left join QuestionStats qa on qa.OwnerName = tu.DisplayName
left join AnswerRanks ar on ar.QuestionId = qa.QuestionId
left join DuplicateLinks dr on dr.PostId = qa.QuestionId
left join ClosedReasonsCount cr on cr.PostId = qa.QuestionId
left join HighActivityUsers hu on hu.Id = tu.Id
where tu.Rank <= 50
  and (qa.IsClosed = 0 or qa.IsClosed is null)
order by tu.Rank, qa.Score desc, ar.AnswerRank
limit 100;