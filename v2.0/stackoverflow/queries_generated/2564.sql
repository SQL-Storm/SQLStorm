-- {"query": "2564.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1523} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    inner join RecursiveTagHierarchy r on t.Count < r.Count and not t.TagName = any(r.Path)
    where r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostScoresWithRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate) as UserPostOrder
    from Posts p
    where p.PostTypeId in (1,2) -- Questions and Answers
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionDate,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        a.ParentId as AnswerParentId,
        case 
            when a.Score >= q.Score then 'CompetingWithQuestion'
            else 'UnderPerforming' 
        end as AnswerPerformance
    from PostScoresWithRanks q
    left join PostScoresWithRanks a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.ScoreRank <= 100
),
AnswerCommentsSummary as (
    select
        c.PostId,
        count(*) as CommentCount,
        count(distinct c.UserId) as DistinctCommenters,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.PostId in (select AnswerId from TopQuestionsWithAnswers)
    group by c.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.CreationDate between u.CreationDate and u.CreationDate + interval '30 days') as PostsInFirst30Days,
        sum(coalesce(cmt.CommentCount, 0)) filter (where p.PostTypeId = 1) as CommentsOnQuestions,
        sum(coalesce(cmt.CommentCount, 0)) filter (where p.PostTypeId = 2) as CommentsOnAnswers
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join AnswerCommentsSummary cmt on cmt.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
DuplicatesWithClosure as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        c.Name as LinkTypeName,
        ph.Comment as CloseReason,
        ph.CreationDate as CloseDate
    from PostLinks pl
    inner join LinkTypes c on c.Id = pl.LinkTypeId and c.Name = 'Duplicate'
    left join PostHistory ph on ph.PostId = pl.PostId and ph.PostHistoryTypeId = 10 -- Post Closed
        and ph.Comment = '101' -- Duplicate close reason code
    where pl.PostId in (select Id from Posts where PostTypeId = 1)
),
UserTagExpertise as (
    select
        u.Id as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2),'><')) as Tag,
        count(p.Id) as PostsPerTag
    from Users u
    inner join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    group by u.Id, Tag
),
TopUserTagExpertise as (
    select distinct on (Tag)
        UserId,
        Tag,
        PostsPerTag,
        rank() over (partition by Tag order by PostsPerTag desc) as TagRank
    from UserTagExpertise
    order by Tag, PostsPerTag desc
)
select 
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ua.PostsInFirst30Days,
    ua.CommentsOnQuestions,
    ua.CommentsOnAnswers,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadgeCount,
    tq.QuestionId,
    tq.Title as QuestionTitle,
    tq.QuestionDate,
    tq.AnswerId,
    tq.AnswerOwner,
    tq.AnswerScore,
    tq.AnswerPerformance,
    acs.CommentCount as AnswerCommentCount,
    acs.DistinctCommenters as AnswerCommenters,
    acs.LastCommentDate,
    dtc.DuplicateQuestionId,
    dtc.OriginalQuestionId,
    dtc.LinkTypeName,
    dtc.CloseReason,
    dtc.CloseDate,
    rth.Level as TagHierarchyLevel,
    rth.Path as TagHierarchyPath,
    tut.Tag as UserTopTag,
    tut.PostsPerTag as UserPostsInTag,
    tut.TagRank
from UserBadgeStats ubs
inner join UserActivityWindow ua on ua.UserId = ubs.UserId
left join TopQuestionsWithAnswers tq on tq.QuestionOwner = ubs.UserId and tq.AnswerScore is not null
left join AnswerCommentsSummary acs on acs.PostId = tq.AnswerId
left join DuplicatesWithClosure dtc on dtc.DuplicateQuestionId = tq.QuestionId
left join RecursiveTagHierarchy rth on rth.TagName = (
    select Tag from UserTagExpertise ute where ute.UserId = ubs.UserId order by PostsPerTag desc limit 1
)
left join TopUserTagExpertise tut on tut.UserId = ubs.UserId and tut.Tag = rth.TagName
where ubs.Reputation > 5000
order by ubs.Reputation desc, ua.PostsInFirst30Days desc, tq.QuestionDate desc
limit 50;