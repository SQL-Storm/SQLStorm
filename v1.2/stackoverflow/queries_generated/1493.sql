-- {"query": "1493.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1079} 
with RecursiveTagAggregates as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count as TagCount,
        p.Id as PostId,
        p.PostTypeId,  -- 1=Question, 2=Answer...
        p.CreationDate,
        u.Id as OwnerUserId,
        u.Reputation,
        u.DisplayName,
        ba.BadgeCount,
        row_number() over (partition by t.Id order by p.Score desc NULLS LAST) as rn
    from Tags t
    left join posts p 
        on p.PostTypeId = 1 and -- tag applied to questions
        (position('<' || t.TagName || '>' in p.Tags) > 0)
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as BadgeCount
        from Badges 
        where TagBased = 1 
        group by UserId
    ) ba on u.Id = ba.UserId
),
TopTagQuestions as (
    select * 
    from RecursiveTagAggregates
    where rn <= 5
),
AnswersAndScores as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        u.Reputation as AnswererReputation,
        coalesce((select percentile_cont(0.9) within group (order by v.CreationDate asc)
            from Votes v
            where v.PostId = a.Id
              and v.VoteTypeId = 2 -- UpMod
        ), a.CreationDate) as FirstUpvoteDate
    from posts a 
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
PostsWithAnswerScores as (
    select
        q.PostId as QuestionId,
        q.TagId,
        q.TagName,
        q.CreationDate as QuestionCreation,
        q.Rn,
        usr.DisplayName as QuestionOwner,
        q.Reputation as QuestionOwnerReputation,
        ans.AnswerId,
        ans.AnswerScore,
        ans.AnswererReputation,
        ans.FirstUpvoteDate
    from TopTagQuestions q
    left join AnswersAndScores ans on ans.QuestionId = q.PostId        
    left join Users usr on usr.Id = (select p.OwnerUserId from Posts p where p.Id = q.PostId)
),
FinalSelectedPosts as (
    select 
        pwq.*,
        -- Calculate detailed engagement score using window functions
        sum(pwq.AnswerScore) over (partition by pwq.TagId) as TotalAnswerScoreForTag,
        count(pwq.AnswerId) over (partition by pwq.TagId) as AnswerCountPerTag,
        avg(pwq.AnswererReputation) over (partition by pwq.TagId) as AvgAnswererReputationPerTag,
        case 
          when pwq.AnswerScore > (
              select percentile_cont(0.95) within group (order by Score) from posts where PostTypeId = 2 and ParentId = pwq.QuestionId
          ) then 1 else 0 
        end as IsTopAnswerInPercentile,
        -- String expression & Null inspection
        concat_ws(
           ' | ', 
            coalesce(pwq.TagName,'[NoTag]'), 
            coalesce(nullif(pwq.QuestionOwner,''),'[Anonymous]'),
            coalesce(cast(pwq.QuestionOwnerReputation as varchar),'0'),
            cast(pwq.TotalAnswerScoreForTag as varchar)
        ) as CompositeTextSummary,
        -- Use correlated subquery with null-safe checks on comments count anchored by badge holders' density
        (
         select count(1) from comments cm 
         join users cmu on cmu.id = cm.UserId
         join badges b on b.UserId = cmu.Id
         where cm.PostId = pwq.QuestionId 
           and b.TagBased = 1
           and cm.CreationDate > (pwq.QuestionCreation - interval '30 day')
        ) as TaggedBadgeCommentsLast30d
    from PostsWithAnswerScores pwq
),
DistinctTagNames as (
    select TagName from Tags where count > 500 union
    select 'SQL' union
    select 'java' minus
    select TagName from Tags where IsModeratorOnly=1
)
select 
    fsp.QuestionId,
    fsp.TagId, 
    dt.TagName as FilteredTagName,
    fsp.QuestionCreation,
    fsp.QuestionOwner,
    fsp.QuestionOwnerReputation,
    fsp.AnswerId,
    fsp.AnswerScore,
    fsp.AnswererReputation,
    fsp.IsTopAnswerInPercentile,
    fsp.CompositeTextSummary,
    fsp.TaggedBadgeCommentsLast30d
from FinalSelectedPosts fsp
join DistinctTagNames dt on dt.TagName = fsp.TagName
where fsp.TotalAnswerScoreForTag > 50
order by fsp.TotalAnswerScoreForTag desc, fsp.TaggedBadgeCommentsLast30d desc;