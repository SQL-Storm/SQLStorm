-- {"query": "2182.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1298} 
with RecentTopQuestions as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName as OwnerName,
        count(v.Id) filter (where vt.Name = 'UpMod') as UpVotes,
        count(v.Id) filter (where vt.Name = 'DownMod') as DownVotes,
        count(distinct c.Id) as CommentCount,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join VoteTypes vt on v.VoteTypeId = vt.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
      and p.CreationDate >= current_date - interval '30 days'
    group by p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName
    having count(v.Id) filter (where vt.Name = 'UpMod') > 20
),
AcceptedAnswerScores as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        coalesce(a.Score, 0) as AnswerScore,
        u.DisplayName as AnswerOwner,
        row_number() over (partition by q.Id order by coalesce(a.Score,0) desc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
QuestionsWithAcceptedAnswers AS (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.OwnerName,
        r.AnswerId,
        r.AnswerScore,
        r.AnswerOwner
    from RecentTopQuestions q
    left join AcceptedAnswerScores r 
      on r.QuestionId = q.Id and r.AnswerRank = 1
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        rank() over (order by count(distinct case when b.Class = 1 then b.Id end) desc) as GoldBadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionCloseStats as (
    select
        p.Id,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
        array_agg(distinct crt.Name) filter (where ph.PostHistoryTypeId = 10) as CloseReasons
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where p.PostTypeId = 1
    group by p.Id
),
CombinedResults as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.OwnerName,
        q.CreationDate,
        q.AnswerId,
        q.AnswerScore,
        q.AnswerOwner,
        ugs.GoldBadges,
        ugs.SilverBadges,
        ugs.BronzeBadges,
        qcs.CloseVotesCount,
        qcs.CloseReasons,
        -- complex string expression: truncated title with badges info
        substring(q.Title from 1 for 50) || '...' || 
        coalesce(' [Gold:'|| ugs.GoldBadges || ', Silver:' || ugs.SilverBadges || ', Bronze:' || ugs.BronzeBadges || ']', '') as TitleSummary,
        -- complex NULL-aware calculation: normalized score per view, treat zero views to avoid division by zero
        case when q.ViewCount > 0 then (q.Score::float / q.ViewCount) else null end as ScorePerView,
        -- window function: rank of answer score among all accepted answers
        rank() over (order by q.AnswerScore desc nulls last) as AnswerScoreRank
    from QuestionsWithAcceptedAnswers q
    left join UserBadgeStats ugs on ugs.DisplayName = q.AnswerOwner
    left join QuestionCloseStats qcs on qcs.Id = q.Id
)
select
    cr.QuestionId,
    cr.Title,
    cr.TitleSummary,
    cr.Score,
    cr.ViewCount,
    cr.ScorePerView,
    cr.OwnerName,
    cr.CreationDate,
    cr.AnswerId,
    cr.AnswerScore,
    cr.AnswerOwner,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.CloseVotesCount,
    array_to_string(cr.CloseReasons, ', ') as CloseReasons,
    cr.AnswerScoreRank
from CombinedResults cr
where (cr.CloseVotesCount is null or cr.CloseVotesCount = 0)
union
select
    p.Id,
    p.Title,
    substring(p.Title from 1 for 50) || '...(Closed)' as TitleSummary,
    p.Score,
    p.ViewCount,
    u.DisplayName,
    p.CreationDate,
    null,
    null,
    null,
    null,
    null,
    null,
    1 as CloseVotesCount,  -- dummy count to mark closed posts in this union leg
    'Closed (shown separately)',
    null
from Posts p
left join Users u on p.OwnerUserId = u.Id
join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
where p.PostTypeId = 1
order by Score desc, ViewCount desc
limit 100;