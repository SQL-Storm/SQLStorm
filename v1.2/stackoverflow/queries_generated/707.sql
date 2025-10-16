-- {"query": "707.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1483} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate >= current_date - interval '1 year'
),
TopTagQuestions as (
    select
        Id, TagName, PostId, Score, ViewCount, CreationDate, OwnerUserId, DisplayName
    from RecursiveTagCounts
    where rn <= 10
),
UserBadgeStats as (
    select
        b.UserId,
        max(case when b.Class = 1 then 1 else 0 end) as HasGold,
        count(case when b.Class = 2 then 1 end) as SilverCount,
        count(case when b.Class = 3 then 1 end) as BronzeCount,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(c.Id) as CommentsCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserAggregated as (
    select
        a.Id,
        a.DisplayName,
        a.Reputation,
        a.QuestionsCount,
        a.AnswersCount,
        a.CommentsCount,
        b.HasGold,
        b.SilverCount,
        b.BronzeCount,
        a.UserRank
    from UserActivityWindow a
    left join UserBadgeStats b on b.UserId = a.Id
),
PostLinkSummary as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
PostScoreWindow as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        avg(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 5 preceding and current row) as MovingAvgScore,
        max(p.Score) over (partition by p.OwnerUserId) as MaxUserScore,
        min(p.Score) over (partition by p.OwnerUserId) as MinUserScore
    from Posts p
    where p.PostTypeId = 1
),
FilteredPosts as (
    select
        ps.*,
        pls.LinkedCount,
        pls.DuplicateCount,
        ua.DisplayName as OwnerDisplayName,
        ua.Reputation as OwnerReputation,
        ua.HasGold,
        ua.SilverCount,
        ua.BronzeCount,
        ua.UserRank
    from PostScoreWindow ps
    left join PostLinkSummary pls on pls.PostId = ps.Id
    left join UserAggregated ua on ua.Id = ps.OwnerUserId
    where ps.Score > 0 and ps.ViewCount > 1000
),
DuplicateQuestionCounts as (
    select
        RelatedPostId as QuestionId,
        count(*) as DuplicateCount
    from PostLinks
    where LinkTypeId = 3
    group by RelatedPostId
),
FinalQuestions as (
    select
        fp.Id,
        fp.Title,
        fp.Score,
        fp.ViewCount,
        fp.Tags,
        fp.CreationDate,
        fp.OwnerUserId,
        fp.OwnerDisplayName,
        fp.OwnerReputation,
        fp.HasGold,
        fp.SilverCount,
        fp.BronzeCount,
        fp.UserRank,
        fp.MovingAvgScore,
        fp.MaxUserScore,
        fp.MinUserScore,
        coalesce(dqc.DuplicateCount, 0) as DuplicateCount,
        fp.LinkedCount,
        fp.DuplicateCount as OutgoingDuplicateLinks,
        (
            select count(*)
            from Comments c
            where c.PostId = fp.Id
              and c.CreationDate > fp.CreationDate
              and (c.Text ilike '%thank%' or c.Text ilike '%helpful%')
        ) as ThankYouCommentsCount
    from FilteredPosts fp
    left join DuplicateQuestionCounts dqc on dqc.QuestionId = fp.Id
)
select
    fq.Id as QuestionId,
    fq.Title,
    fq.Score,
    fq.ViewCount,
    fq.Tags,
    fq.CreationDate,
    fq.OwnerUserId,
    fq.OwnerDisplayName,
    fq.OwnerReputation,
    fq.HasGold,
    fq.SilverCount,
    fq.BronzeCount,
    fq.UserRank,
    fq.MovingAvgScore,
    fq.MaxUserScore,
    fq.MinUserScore,
    fq.DuplicateCount,
    fq.LinkedCount,
    fq.OutgoingDuplicateLinks,
    fq.ThankYouCommentsCount,
    case
        when fq.DuplicateCount > 5 then 'Hot Duplicate'
        when fq.Score > 50 and fq.ViewCount > 10000 then 'Popular Question'
        else 'Regular Question'
    end as QuestionStatus,
    -- Complicated string expression with NULL logic
    concat(
        coalesce(substring(fq.Title from 1 for 30), 'No Title'), '...',
        ' [Tags: ', coalesce(fq.Tags, 'None'), ']',
        ' | Owner: ', coalesce(fq.OwnerDisplayName, 'Anonymous'),
        ' (Rep: ', coalesce(cast(fq.OwnerReputation as varchar), '0'), ')'
    ) as Summary,
    -- Correlated subquery for top answer score
    (
        select max(a.Score)
        from Posts a
        where a.ParentId = fq.Id and a.PostTypeId = 2
    ) as TopAnswerScore,
    -- Window function for rank of question score among all filtered questions
    rank() over (order by fq.Score desc, fq.ViewCount desc) as QuestionScoreRank
from FinalQuestions fq
where fq.UserRank <= 1000
order by fq.Score desc, fq.ViewCount desc
limit 100;