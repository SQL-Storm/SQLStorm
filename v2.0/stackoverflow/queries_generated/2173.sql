-- {"query": "2173.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1469} 
with RecursivePostTags as (
    select
        p.Id as PostId,
        p.Tags,
        unnest(string_to_array(trim(both '<>' from coalesce(p.Tags, '')), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TopUsersByReputation as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        row_number() over (order by u.Reputation desc) as rn
    from Users u
    where u.Reputation > 10000
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
QuestionsWithAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(ans_count.AnswerCount, 0) as AnswerCount,
        coalesce(best_answer.Score, 0) as BestAnswerScore,
        best_answer.OwnerUserId as BestAnswerOwner,
        best_answer.CreationDate as BestAnswerDate
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts p_ans
        where p_ans.PostTypeId = 2
        group by ParentId
    ) ans_count on ans_count.ParentId = q.Id
    left join lateral (
        select p.Id, p.Score, p.OwnerUserId, p.CreationDate
        from Posts p
        where p.PostTypeId = 2 and p.ParentId = q.Id
        order by p.Score desc nulls last, p.CreationDate asc
        limit 1
    ) best_answer on true
    where q.PostTypeId = 1
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        string_agg(distinct crt.Name, ', ') as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
QuestionsFullData as (
    select
        qas.*,
        qcr.CloseReasons,
        uts.Tag,
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.HasTagBasedBadge
    from QuestionsWithAnswerStats qas
    left join QuestionsWithCloseReasons qcr on qcr.PostId = qas.QuestionId
    left join RecursivePostTags uts on uts.PostId = qas.QuestionId
    left join Users u on u.Id = qas.BestAnswerOwner
    left join UserBadgeSummary ub on ub.UserId = u.Id
),
UserAnswerRankings as (
    select
        p.OwnerUserId,
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        rank() over(partition by p.OwnerUserId order by p.Score desc nulls last) as AnswerRank
    from Posts p
    where p.PostTypeId = 2 and p.OwnerUserId is not null
),
HighScoreAnswers as (
    select
        uas.OwnerUserId,
        uas.AnswerId,
        uas.QuestionId,
        uas.Score,
        uas.AnswerRank
    from UserAnswerRankings uas
    where uas.AnswerRank <= 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v2.Id) filter (where v2.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Votes v2 on v2.UserId = u.Id
    group by u.Id
),
DuplicatesAndLinkedPosts as (
    select
        pl1.PostId,
        pl1.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl1
    join LinkTypes lt on lt.Id = pl1.LinkTypeId
    join Posts p1 on p1.Id = pl1.PostId
    join Posts p2 on p2.Id = pl1.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),
FinalResult as (
    select
        qfd.QuestionId,
        qfd.Title as QuestionTitle,
        qfd.QuestionCreation,
        qfd.ViewCount,
        qfd.QuestionScore,
        qfd.AnswerCount,
        qfd.BestAnswerScore,
        coalesce(uas.QuestionsPosted,0) as UserQuestions,
        coalesce(uas.AnswersPosted,0) as UserAnswers,
        coalesce(uas.CommentsMade,0) as UserComments,
        coalesce(uas.UpVotesGiven,0) as UserUpVotesGiven,
        coalesce(uas.DownVotesGiven,0) as UserDownVotesGiven,
        qfd.Reputation as BestAnswerUserRep,
        qfd.GoldBadges,
        qfd.SilverBadges,
        qfd.BronzeBadges,
        qfd.HasTagBasedBadge,
        qfd.CloseReasons,
        qfd.Tag,
        dup.PostId as DuplicatePostId,
        dup.RelatedPostId as DuplicateOfPostId,
        dup.RelatedPostTitle as DuplicateOfPostTitle,
        row_number() over (partition by qfd.QuestionId order by qfd.BestAnswerScore desc nulls last) as rn
    from QuestionsFullData qfd
    left join UserActivitySummary uas on uas.UserId = qfd.UserId
    left join DuplicatesAndLinkedPosts dup on dup.PostId = qfd.QuestionId and dup.LinkTypeName = 'Duplicate'
)
select * from FinalResult
where rn = 1
order by CloseReasons nulls first, UserComments desc
limit 100;