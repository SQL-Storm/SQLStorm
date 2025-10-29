-- {"query": "2408.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1389} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.OwnerUserId, -1) as OwnerUserId,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.Reputation,
        u.Location,
        u.CreationDate as UserCreationDate,
        coalesce(bc.BadgeCount,0) as BadgeCount
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        where Class = 1 -- Gold badges only
        group by UserId
    ) bc on bc.UserId = p.OwnerUserId
    where p.PostTypeId in (1,2) -- Questions and Answers
      and p.CreationDate >= '2019-01-01'
),
AggregatedVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    inner join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
CTEQuestionsWithActivity as (
    select
        fp.*,
        av.UpVotes,
        av.DownVotes,
        ph.PostHistoryTypeId,
        ph.CreationDate as LastEditDate,
        cr.Name as CloseReasonName,
        -- Detect if question is closed in post history
        case when max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) over (partition by fp.Id) = 1 then 1 else 0 end as IsClosed
    from FilteredPosts fp
    left join AggregatedVotes av on av.PostId = fp.Id
    left join PostHistory ph on ph.PostId = fp.Id
    left join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
    where fp.PostTypeId = 1
),
RankedAnswers as (
    select
        a.*,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as AnswerCountByQuestion,
        u.DisplayName as AnswerOwnerDisplayName,
        av.UpVotes as AnswerUpVotes,
        av.DownVotes as AnswerDownVotes
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    left join AggregatedVotes av on av.PostId = a.Id
    where a.PostTypeId = 2
),
FinalSelection as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.UpVotes as QuestionUpVotes,
        q.DownVotes as QuestionDownVotes,
        q.Reputation as QuestionOwnerReputation,
        q.BadgeCount as QuestionOwnerGoldBadges,
        q.IsClosed,
        q.CloseReasonName,
        q.LastEditDate as QuestionLastEdit,
        r.AnswerRank,
        r.Id as AnswerId,
        r.Score as AnswerScore,
        r.AnswerUpVotes,
        r.AnswerDownVotes,
        r.AnswerCountByQuestion,
        r.AnswerOwnerDisplayName,
        -- Calculate relative answer score percentile per question
        percent_rank() over (partition by r.ParentId order by r.Score) as AnswerScorePercentile,
        -- complex string logic: normalized tag list length
        length(replace(replace(coalesce(q.Tags, ''), '<', ''), '>', '')) / nullif(array_length(string_to_array(replace(coalesce(q.Tags, ''), '><', ','), ','), 1), 0) as AvgTagNameLength,
        -- NULL logic: check if answer has accepted flag from question
        case when q.AcceptedAnswerId = r.Id then 1 else 0 end as IsAccepted,
        -- Correlated subquery to get last comment text length on answer
        (select max(length(c.Text))
         from Comments c
         where c.PostId = r.Id
         and c.CreationDate > r.CreationDate - interval '30 days') as MaxRecentCommentLength
    from CTEQuestionsWithActivity q
    left join RankedAnswers r on r.ParentId = q.Id
    where r.AnswerRank is not null
)
select * from FinalSelection
where QuestionViews > 1000
  and QuestionScore > 5
  and (IsClosed = 0 or CloseReasonName is null)
union
select
    q.Id as QuestionId,
    q.Title,
    q.Tags,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViews,
    q.UpVotes as QuestionUpVotes,
    q.DownVotes as QuestionDownVotes,
    q.Reputation as QuestionOwnerReputation,
    q.BadgeCount as QuestionOwnerGoldBadges,
    q.IsClosed,
    q.CloseReasonName,
    q.LastEditDate as QuestionLastEdit,
    null::int as AnswerRank,
    null::int as AnswerId,
    null::int as AnswerScore,
    null::int as AnswerUpVotes,
    null::int as AnswerDownVotes,
    null::int as AnswerCountByQuestion,
    null::varchar as AnswerOwnerDisplayName,
    null::float as AnswerScorePercentile,
    length(replace(replace(coalesce(q.Tags, ''), '<', ''), '>', '')) / nullif(array_length(string_to_array(replace(coalesce(q.Tags, ''), '><', ','), ','), 1), 0) as AvgTagNameLength,
    null::int as IsAccepted,
    null::int as MaxRecentCommentLength
from CTEQuestionsWithActivity q
where q.Id not in (select ParentId from RankedAnswers)
order by QuestionViews desc, QuestionScore desc, AnswerScore desc nulls last
limit 100;