-- {"query": "2158.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1293} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
BadgeRanked as (
    select * from RecursiveUserBadges where rn <= 3
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        p.Tags,
        -- Number of distinct users who answered this question
        (
            select count(distinct a.OwnerUserId)
            from Posts a
            where a.PostTypeId = 2 and a.ParentId = p.Id and a.OwnerUserId is not null
        ) as DistinctAnswerers,
        -- Max score of answers
        (
            select max(score)
            from Posts a
            where a.PostTypeId = 2 and a.ParentId = p.Id
        ) as MaxAnswerScore,
        -- Number of comments on question
        (
            select count(*)
            from Comments c
            where c.PostId = p.Id
        ) as QuestionCommentCount
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '1 year'
),
QuestionWithCloseInfo as (
    select
        qs.*,
        ph.Comment as CloseReasonJson,
        crt.Name as CloseReasonName
    from QuestionStats qs
    left join PostHistory ph on ph.PostId = qs.QuestionId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
),
AnswerScores as (
  select
    a.ParentId as QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId,
    a.Score,
    row_number() over (partition by a.ParentId order by a.Score desc) as AnswerRank
  from Posts a
  where a.PostTypeId = 2
),
RankedAnswers as (
    select *
    from AnswerScores
    where AnswerRank <= 5
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between 365 preceding and current row) as QuestionsLastYear,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between 365 preceding and current row) as AnswersLastYear
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopTagsPerUser as (
    select distinct
        p.OwnerUserId as UserId,
        unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as Tag,
        count(*) over (partition by p.OwnerUserId, unnest(string_to_array(trim(both '<>' from p.Tags), '><'))) as TagUseCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TopTagsRanked as (
    select
        UserId,
        Tag,
        TagUseCount,
        row_number() over (partition by UserId order by TagUseCount desc) as rn
    from TopTagsPerUser
),
Top3Tags as (
    select UserId, array_agg(Tag order by TagUseCount desc) as TopTags
    from TopTagsRanked
    where rn <= 3
    group by UserId
)
select
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.DistinctAnswerers,
    q.MaxAnswerScore,
    q.QuestionCommentCount,
    q.CloseReasonName,
    ba.BadgeName,
    ba.Class as BadgeClass,
    ta.TagName,
    pld.LinkTypeName,
    ra.AnswerId,
    ra.OwnerUserId as AnswerOwnerUserId,
    ra.Score as AnswerScore,
    u.DisplayName as AnswerOwnerDisplayName,
    ua.QuestionsLastYear,
    ua.AnswersLastYear,
    coalesce(tt.TopTags, array[]::varchar[]) as UserTopTags,
    -- String concatenation with NULL logic example: user and question titles combined
    concat_ws(' - ', u.DisplayName, q.Title) as UserQuestionSummary,
    -- Conditional complicated predicate
    case
        when q.Score > 10 and q.AnswerCount > 5 then 'Hot Question'
        when q.Score > 0 then 'Warm Question'
        else 'Cold Question'
    end as QuestionHeatStatus
from QuestionWithCloseInfo q
left join RankedAnswers ra on ra.QuestionId = q.QuestionId
left join Users u on u.Id = ra.OwnerUserId
left join BadgeRanked ba on ba.UserId = q.OwnerUserId
left join PostLinkDetails pld on pld.PostId = q.QuestionId
left join UserActivityWindow ua on ua.UserId = q.OwnerUserId
left join Top3Tags tt on tt.UserId = q.OwnerUserId
left join Tags ta on ta.TagName = any(coalesce(tt.TopTags, array[]::varchar[]))
where
    (q.CloseReasonName is null or q.CloseReasonName = 'Duplicate')
    and (ra.AnswerScore is null or ra.AnswerScore > 0)
order by q.CreationDate desc, q.Score desc
limit 100;