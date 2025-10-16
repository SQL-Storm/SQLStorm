-- {"query": "4011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1158} 
with RecursiveQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        row_number() over (partition by u.Id order by p.Score desc) rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
TopQuestions as (
    select * from RecursiveQuestions where rn <= 10
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        array_agg(distinct u.DisplayName) filter (where u.DisplayName is not null) as Answerers
    from Posts a
    left join Votes v on a.Id = v.PostId
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
    group by a.ParentId
),
CloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
BadgeSummary as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        string_agg(distinct Name, ', ') as BadgeNames
    from Badges
    group by UserId
),
QuestionWithDetails as (
    select
        q.QuestionId,
        q.Title,
        q.Tags,
        q.OwnerName,
        q.OwnerReputation,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        coalesce(a.AnswerCount,0) as AnswerCount,
        coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(a.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(a.TotalUpVotes,0) as TotalUpVotesOnAnswers,
        coalesce(a.TotalDownVotes,0) as TotalDownVotesOnAnswers,
        coalesce(cr.CloseReason, 'Open') as CloseReason,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        b.BadgeNames,
        array_length(a.Answerers,1) as DistinctAnswererCount,
        -- Calculate how many characters are there in tags (remove angle brackets and split count)
        array_length(string_to_array(trim(both '<>' from q.Tags), '><'),1) as TagCount
    from TopQuestions q
    left join AnswerStats a on q.QuestionId = a.QuestionId
    left join CloseReasons cr on q.QuestionId = cr.PostId
    left join Users u on u.DisplayName = q.OwnerName
    left join BadgeSummary b on u.Id = b.UserId
)
select
    q.QuestionId,
    q.Title,
    case 
        when q.TagCount > 5 then 'Multi-tag'
        when q.TagCount between 1 and 5 then 'Few tags'
        else 'No tags'
    end as TagGroup,
    q.OwnerName,
    q.OwnerReputation,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    q.AnswerCount,
    q.AvgAnswerScore,
    q.MaxAnswerScore,
    q.TotalUpVotesOnAnswers,
    q.TotalDownVotesOnAnswers,
    q.CloseReason,
    coalesce(q.GoldBadges,0) as GoldBadges,
    coalesce(q.SilverBadges,0) as SilverBadges,
    coalesce(q.BronzeBadges,0) as BronzeBadges,
    q.BadgeNames,
    q.DistinctAnswererCount,
    -- Window function - rank questions by score partitioned by TagGroup
    rank() over (partition by 
        case 
            when q.TagCount > 5 then 'Multi-tag'
            when q.TagCount between 1 and 5 then 'Few tags'
            else 'No tags'
        end
        order by q.Score desc) as ScoreRankInTagGroup,
    -- Correlated subquery: total comments for this question
    (select count(*) from Comments c where c.PostId = q.QuestionId) as CommentCount,
    -- String manipulation example: concatenate owner name and tags
    concat(coalesce(q.OwnerName,'Anonymous'), ' | Tags: ', coalesce(q.Tags,'<none>')) as OwnerAndTags,
    -- NULL logic: if accepted answer is null, show 'No accepted answer' else the Id
    coalesce(cast(q.AcceptedAnswerId as varchar),'No accepted answer') as AcceptedAnswerIdDisplay
from QuestionWithDetails q
where q.Score > (
    select avg(Score)*0.7 from Posts where PostTypeId=1
)
order by q.Score desc
limit 20;