-- {"query": "5086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1065} 
with question_votes as (
    select
        p.Id as QuestionId,
        p.CreationDate as QuestionCreationDate,
        p.OwnerUserId as OwnerUserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        count(distinct v.Id) as TotalVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.CreationDate, p.OwnerUserId
),
answer_stats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore,
        avg(nullif(p.Score,0)) as AvgNonZeroAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
user_badge_rank as (
    select
        u.Id as UserId,
        count(b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        dense_rank() over(order by count(b.Id) desc nulls last) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
edit_activity as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as Edits,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
        count(distinct ph.UserId) filter (where ph.PostHistoryTypeId in (4,5,6) and ph.UserId is not null) as DistinctEditors
    from PostHistory ph
    group by ph.PostId
)
select
    qv.QuestionId,
    coalesce(u.DisplayName, p.OwnerDisplayName, '[unknown user]') as AuthorDisplayName,
    u.Reputation,
    qv.QuestionCreationDate,
    upper(left(p.Title,1)) || lower(substring(p.Title from 2 for 49)) as FormattedTitle,
    case 
        when position('<sql>' in coalesce(p.Tags,'')) > 0 then true else false end as HasSqlTag,
    qv.UpVotes,
    qv.DownVotes,
    qv.TotalVotes,
    ast.AnswerCount,
    ast.MaxAnswerScore,
    ast.MinAnswerScore,
    cast(ast.AvgNonZeroAnswerScore as numeric(10,2)) as AvgNonZeroAnswerScore,
    e.Edits,
    e.FirstEditDate,
    e.LastEditDate,
    e.DistinctEditors,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.BadgeRank,
    case
        when (ast.AnswerCount is null or ast.AnswerCount = 0) and qv.UpVotes > 10 then 'Unanswered But Popular'
        when ast.MaxAnswerScore > 5 then 'Highly Rated Answers'
        when qv.DownVotes > qv.UpVotes then 'Controversial'
        else 'Normal'
    end as QuestionCategory,
    lead(qv.QuestionId) over (order by qv.TotalVotes desc nulls last) as NextQuestionIdByVotes,
    lag(qv.QuestionId) over (order by qv.TotalVotes desc nulls last) as PrevQuestionIdByVotes
from question_votes qv
inner join Posts p on p.Id = qv.QuestionId
left join Users u on u.Id = qv.OwnerUserId
left join answer_stats ast on ast.QuestionId = qv.QuestionId
left join user_badge_rank ub on ub.UserId = coalesce(qv.OwnerUserId, -1)
left join edit_activity e on e.PostId = qv.QuestionId
where 
    (qv.UpVotes > 5 or ast.MaxAnswerScore > 3 or ub.GoldBadges > 0)
    and not (p.Title is null or trim(p.Title) = '')
    and (p.ViewCount is null or p.ViewCount > 0)
    and (
        extract(year from p.CreationDate) = extract(year from current_date) 
        or e.Edits > 0
    )
order by
    qv.TotalVotes desc nulls last,
    ast.AnswerCount desc nulls last,
    ub.BadgeRank asc nulls last
limit 100;