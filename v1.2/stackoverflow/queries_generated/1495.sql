-- {"query": "1495.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1352} 
with RecursiveBadgeStats as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        u.Reputation,
        u.CreationDate,
        u.Location,
        dense_rank() over (partition by b.UserId order by b.Class, b.Date) as BadgeRank,
        row_number() over (partition by b.UserId order by b.Date desc) as RecentBadgeRowNum
    from Badges b
    join Users u on u.Id = b.UserId
    where b.TagBased = 0 and b.Class in (1, 2, 3)
),
RecentPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.ClosedDate,
        FoodTag = array_position(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'), 'food'),
        RowNum = row_number() over (partition by p.OwnerUserId order by p.CreationDate desc)
    from Posts p
    where p.PostTypeId in (1, 2) and p.CreationDate > (current_date - interval '1 year')
),
PostDuplicates as (
    select
        l.PostId,
        l.RelatedPostId,
        l.CreationDate,
        can_dupes = count(*) filter (where l.LinkTypeId = 3) over (partition by l.PostId)
    from PostLinks l
    where l.LinkTypeId = 3
),
QuestionAnswerAggregate as (
    select
        q.Id as QuestionId, q.Title, q.OwnerUserId as AskerId, q.CreationDate as QuestionCreated,
        count(a.Id) as TotalAnswers,
        sum(case when a.Score > 2 then 1 else 0 end) as HighlyVotedAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(coalesce(a.Score,0)) filter (where a.PostTypeId = 2) as AverageAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2 and a.CreationDate > q.CreationDate
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
UserEngagement as (
    select
        u.Id, u.DisplayName, u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as NumberQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as NumberAnswers,
        sum(coalesce(p.Score, 0)) as TotalPostScore,
        count(distinct c.Id) as TotalComments,
        avg(v.Score) over (partition by u.Id) as AvgVoteScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
FilteredHighImpactUsers as (
    select 
        ue.Id, ue.DisplayName, ue.Reputation,
        total_badges = count(rbs.BadgeName) filter (where rbs.Class = 1),
        silver_badges = count(rbs.BadgeName) filter (where rbs.Class = 2),
        bronze_badges = count(rbs.BadgeName) filter (where rbs.Class = 3),
        ue.NumberQuestions, ue.NumberAnswers, ue.TotalPostScore, ue.TotalComments
    from UserEngagement ue
    left join RecursiveBadgeStats rbs on rbs.UserId = ue.Id
    group by ue.Id, ue.DisplayName, ue.Reputation, ue.NumberQuestions, ue.NumberAnswers, ue.TotalPostScore, ue.TotalComments
    having ue.Reputation > 10000 and ue.NumberAnswers > 50
),
TopQuestionsWithDuplicatesAndStatus as (
    select 
        q.QuestionId,
        q.Title,
        fhi.DisplayName as Asker,
        q.TotalAnswers,
        q.HighlyVotedAnswers,
        q.AverageAnswerScore,
        duplicated.DuplicateQuestionId,
        duplicated.DuplicateLinkDate,
        closed.ClosedDate,
        row_number() over (partition by q.TotalAnswers order by q.TotalAnswers desc, q.QuestionCreated desc) as RNByAnswers
    from QuestionAnswerAggregate q
    left join topqaDupe pq on pq.Id = q.QuestionId
    left join (
        select distinct pl.PostId as QuestionId, pl.RelatedPostId as DuplicateQuestionId, pl.CreationDate as DuplicateLinkDate 
          from PostLinks pl 
          where pl.LinkTypeId = 3
    ) duplicated on duplicated.QuestionId = q.QuestionId
    left join Posts closepost on closepost.Id = q.QuestionId and closepost.ClosedDate is not null
    where q.TotalAnswers > 0
)
select
    fpwt.DuplicateQuestionId,
    fpwt.QuestionId,
    fpwt.Title,
    fpwt.Asker,
    fpwt.TotalAnswers,
    fpwt.HighlyVotedAnswers,
    fpwt.AverageAnswerScore,
    fpwt.ClosedDate,
    fhu.DisplayName as HighRepUser,
    fhu.Reputation,
    fhu.total_badges,
    fhu.silver_badges,
    fhu.bronze_badges,
    rv.rank_pct,
    rb.BadgeName,
    substring(ph.Text from 1 for 200) as RecentEditDescription
from TopQuestionsWithDuplicatesAndStatus fpwt
left join FilteredHighImpactUsers fhu on fhu.Id = fpwt.Asker
left join RecursiveBadgeStats rb on rb.UserId = fhu.Id and rb.BadgeRank = 1
left join PostHistory ph on ph.PostId = fpwt.QuestionId and ph.PostHistoryTypeId = 4 -- Edit title
outer apply (
    select 
        round(100.0 * ntile(100) over (order by fhu.Reputation desc))
        from Users where id = fhu.Id
) rv(rank_pct)
where fpwt.RNByAnswers <= 20
order by fpwt.TotalAnswers desc, fhu.Reputation desc
limit 50;