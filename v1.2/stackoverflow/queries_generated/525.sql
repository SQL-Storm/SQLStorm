-- {"query": "525.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 982} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
), RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        count(c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as PostRank
    from Posts p
    left join Comments c on p.Id = c.PostId
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId in (1, 2)
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.CreationDate, p.Title, p.Tags, p.AcceptedAnswerId
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
), UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct ph.Id) as TotalEdits,
        max(ph.CreationDate) as LastEditDate,
        max(p.LastActivityDate) as LastPostActivity,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join PostHistory ph on p.Id = ph.PostId and ph.UserId = u.Id
    group by u.Id, u.DisplayName
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalEdits,
    ua.LastEditDate,
    ua.LastPostActivity,
    rb.BadgeName,
    rb.Class as BadgeClass,
    rp.Id as PostId,
    rp.PostTypeId,
    rp.Score as PostScore,
    rp.Title,
    rp.Tags,
    rp.CommentCount,
    rp.UpVotes,
    rp.DownVotes,
    case when dup.PostId is not null then 1 else 0 end as IsDuplicate,
    case 
        when rp.PostTypeId = 1 and rp.AcceptedAnswerId is not null then 'HasAcceptedAnswer'
        when rp.PostTypeId = 1 then 'NoAcceptedAnswer'
        else 'N/A'
    end as AcceptedAnswerStatus,
    length(coalesce(rp.Tags, '')) - length(replace(coalesce(rp.Tags, ''), '><', '')) + 1 as TagCount,
    lag(rp.Score) over (partition by rp.OwnerUserId order by rp.CreationDate) as PrevPostScore,
    lead(rp.Score) over (partition by rp.OwnerUserId order by rp.CreationDate) as NextPostScore
from Users u
left join UserActivity ua on u.Id = ua.UserId
left join RecursiveUserBadges rb on u.Id = rb.UserId and rb.BadgeRank = 1
left join RankedPosts rp on u.Id = rp.OwnerUserId and rp.PostRank <= 5
left join DuplicateLinks dup on rp.Id = dup.PostId
where u.Reputation > 5000
and (
    rp.Score > (
        select avg(p2.Score)
        from Posts p2
        where p2.OwnerUserId = u.Id and p2.PostTypeId = rp.PostTypeId
    )
    or rp.Score is null
)
and (
    ua.LastPostActivity > u.CreationDate + interval '1 year'
    or ua.LastPostActivity is null
)
order by u.Reputation desc, rp.Score desc nulls last, rp.CreationDate desc
limit 100;