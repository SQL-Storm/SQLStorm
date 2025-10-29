-- {"query": "2132.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1301} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        p.Score,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as TagRank,
        count(*) over (partition by t.Id) as TagPostCount
    from Tags t
    left join Posts p on p.Tags like '%' || t.TagName || '%'
    where t.TagName is not null
),  
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
RecentClosedQuestions as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        u.DisplayName as ClosedByUser
    from Posts p
    inner join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id::text = ph.Comment
    left join Users u on u.Id = ph.UserId
    where p.PostTypeId = 1
    and ph.CreationDate > current_date - interval '30 days'
),
AnswerStats as (
    select 
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when p.LastActivityDate > current_date - interval '7 days' then 1 else 0 end) as RecentActiveAnswers
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
TopUsersByRepAndVote as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(uv.UpVotes,0) as UpVotes,
        coalesce(uv.DownVotes,0) as DownVotes,
        case when u.Reputation > 0 then round(uv.UpVotes::numeric / nullif(u.Reputation,0), 4) else null end as UpVotesPerReputation
    from Users u
    left join (
        select 
            v.UserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        where v.UserId is not null
        group by v.UserId
    ) uv on uv.UserId = u.Id
    where u.Reputation > 10000
    order by u.Reputation desc
    limit 50
)
select 
    q.Id as QuestionId,
    q.Title,
    qc.AnswerCount,
    qc.AvgAnswerScore,
    qc.MaxAnswerScore,
    qc.RecentActiveAnswers,
    rt.TagName,
    rt.TagRank,
    rt.TagPostCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBadges,
    ubs.LastBadgeDate,
    cu.CloseReasonName,
    cu.CloseDate,
    cu.ClosedByUser,
    tu.DisplayName as TopUserDisplayName,
    tu.Reputation as TopUserReputation,
    tu.UpVotes as TopUserUpVotes,
    tu.DownVotes as TopUserDownVotes,
    tu.UpVotesPerReputation,
    case 
        when q.ViewCount > 10000 then 'High Views'
        when q.ViewCount between 1000 and 10000 then 'Medium Views'
        else 'Low Views'
    end as ViewCountCategory,
    case 
        when q.Score > 10 then 'High Score'
        when q.Score between 0 and 10 then 'Moderate Score'
        else 'Low Score'
    end as ScoreCategory,
    (length(q.Body) - length(replace(q.Body, 'SQL', ''))) / 3 as SQLMentionsCount,
    strpos(lower(coalesce(q.Title, '')), 'performance') > 0 as TitleMentionsPerformance,
    case when lower(coalesce(q.Tags, '')) like '%<sql>%' then 1 else 0 end as HasSQLTag,
    (select count(*) 
     from Comments c 
     where c.PostId = q.Id 
       and c.CreationDate > current_date - interval '14 days') as RecentCommentsCount
from Posts q
left join AnswerStats qc on qc.QuestionId = q.Id
left join RecursiveTagCounts rt on rt.PostId = q.Id and rt.TagRank <= 3
left join UserBadgeSummary ubs on ubs.UserId = q.OwnerUserId
left join RecentClosedQuestions cu on cu.Id = q.Id
left join TopUsersByRepAndVote tu on tu.Id = q.OwnerUserId
where q.PostTypeId = 1
and q.CreationDate between current_date - interval '180 days' and current_date
and (q.Score > 0 or q.ViewCount > 1000)
and (
    (rt.TagName is not null and rt.TagPostCount > 100) 
    or
    (uBs.GoldBadges > 0)
)
order by 
    qc.RecentActiveAnswers desc nulls last,
    q.Score desc nulls last,
    rt.TagPostCount desc nulls last,
    ubs.GoldBadges desc nulls last
limit 100;