-- {"query": "4044.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1486} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> all(r.Path)
    where t2.Count > 10 and r.Level < 3 and t2.IsModeratorOnly = 0
),
TopActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vt.Score), 0) as VoteScoreSum,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select p2.Id, p2.Score
        from Posts p2
        where p2.PostTypeId in (1,2)
    ) vt on vt.Id = p.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(p.Id) > 5
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) filter (where a.Score is not null) as MaxAnswerScore,
        min(a.CreationDate) filter (where a.CreationDate > q.CreationDate) as FirstAnswerDate,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        bool_or(ph.PostHistoryTypeId = 10) as IsClosed,
        ph.Comment as CloseReasonId
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = q.Id
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId in (10,11)
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, ph.Comment
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostWithHistoryRanks as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate) as EditNumber
    from PostHistory ph
),
UserEngagement as (
    select
        u.Id,
        coalesce(count(distinct p.Id),0) as PostCount,
        coalesce(sum(vb.TotalBadges),0) as TotalUserBadges,
        count(distinct c.Id) as CommentCount,
        count(distinct ph.Id) as PostHistoryEdits,
        avg(p.Score) filter (where p.Score is not null) as AvgPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join UserBadgeCounts vb on vb.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
)
select 
    qas.QuestionId,
    substring(qas.Title for 100) as ShortTitle,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.MaxAnswerScore,
    qas.FirstAnswerDate,
    qas.UpVotes,
    qas.DownVotes,
    case when qas.IsClosed then 'Closed' else 'Open' end as QuestionStatus,
    crt.Name as CloseReason,
    ta.TagName,
    ta.Count as TagPopularity,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ue.CommentCount as OwnerCommentCount,
    ue.PostCount as OwnerPostCount,
    ue.PostHistoryEdits as OwnerEditCount,
    ue.AvgPostScore as OwnerAvgPostScore,
    ue.LastPostDate as OwnerLastPostDate,
    first_value(p.LeadPostId) over (partition by qas.QuestionId order by p.Score desc nulls last) as TopAnswerId,
    lead(p.Id) over (partition by qas.QuestionId order by p.Score desc nulls last) as SecondTopAnswerId
from QuestionAnswerStats qas
left join PostLinks pl on pl.PostId = qas.QuestionId and pl.LinkTypeId = 3 -- duplicates
left join CloseReasonTypes crt on crt.Id = nullif(qas.CloseReasonId, '')::smallint
left join RecursiveTagHierarchy ta on ta.TagName = any(string_to_array(substring(qas.Tags from 2 for char_length(qas.Tags)-2), '><'))
left join Users u on u.Id = (
    select psub.OwnerUserId 
    from Posts psub 
    where psub.Id = qas.QuestionId and psub.OwnerUserId is not null
    limit 1
)
left join UserBadgeCounts ub on ub.UserId = u.Id
left join UserEngagement ue on ue.Id = u.Id
left join Posts p on p.ParentId = qas.QuestionId and p.PostTypeId = 2
where qas.AnswerCount > 0
  and qas.QuestionScore > 1
  and (qas.ViewCount > 100 or qas.UpVotes > 5)
  and (ta.Level = 1 or ta.Level = 2)
order by qas.QuestionScore desc nulls last, qas.ViewCount desc nulls last
limit 100;