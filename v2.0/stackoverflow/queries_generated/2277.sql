-- {"query": "2277.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1974} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.TagBased = 0 or b.TagBased is null
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId in (1, 2)  -- Questions and Answers
      and p.CreationDate >= current_date - interval '1 year'
),
PostWithAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.AcceptedAnswerId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        u.Reputation as AnswerOwnerReputation,
        -- window function: Rank answers by score + inverse age (newer answers get higher rank)
        rank() over (partition by q.Id order by a.Score desc, a.CreationDate desc) as AnswerRank
    from FilteredPosts q
    left join FilteredPosts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
TopAnswers as (
    select
        QuestionId,
        Title,
        Tags,
        QuestionScore,
        ViewCount,
        AnswerId,
        AnswerScore,
        AnswerCreationDate,
        AnswerOwnerUserId,
        AnswerOwnerReputation
    from PostWithAnswerStats
    where AnswerRank = 1
),
UserBadgeSummary as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        max(BadgeRank) as TotalBadges
    from RecursiveUserBadges
    group by UserId
),
AnswerVotesAgg as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
RecentCommentsCount as (
    select
        c.PostId,
        count(*) filter (where c.CreationDate >= current_date - interval '30 day') as RecentComments30d
    from Comments c
    group by c.PostId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on ph.Comment::int = crt.Id
    where pht.Name = 'Post Closed'
),
QuestionDuplicates as (
    select distinct
        pl.PostId as QuestionId,
        pl.RelatedPostId as DuplicateOfQuestionId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
ComplexQuestionAnalytics as (
    select
        q.Id as QuestionId,
        q.Title,
        u.DisplayName as QuestionOwner,
        u.Reputation as QuestionOwnerReputation,
        q.Score,
        q.ViewCount,
        coalesce(av.UpVotes,0) as AnswerUpVotes,
        coalesce(av.DownVotes,0) as AnswerDownVotes,
        coalesce(rc.RecentComments30d,0) as RecentComments,
        coalesce(cb.GoldBadges,0) as QuestionOwnerGoldBadges,
        coalesce(cb.SilverBadges,0) as QuestionOwnerSilverBadges,
        coalesce(cb.BronzeBadges,0) as QuestionOwnerBronzeBadges,
        d.DuplicateOfQuestionId,
        cr.CloseReasonName,
        cr.CloseDate,
        row_number() over (partition by u.Id order by q.Score desc nulls last) as UserQuestionRank,
        -- complex string expression: sanitize tags removing < and > characters and concat with title
        regexp_replace(q.Tags, '[<>]', '', 'g') || ' :: ' || coalesce(q.Title, 'No Title') as TagTitleConcat,
        -- correlated subquery to find count of distinct users who answered this question
        (select count(distinct a.OwnerUserId) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2 and a.OwnerUserId is not null) as DistinctAnswerersCount
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join AnswerVotesAgg av on av.PostId = q.AcceptedAnswerId
    left join RecentCommentsCount rc on rc.PostId = q.Id
    left join UserBadgeSummary cb on cb.UserId = q.OwnerUserId
    left join QuestionDuplicates d on d.QuestionId = q.Id
    left join QuestionCloseReasons cr on cr.PostId = q.Id
    where q.PostTypeId = 1
      and q.CreationDate >= current_date - interval '1 year'
),
UnionedUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        'Question' as ActivityType,
        p.Id as PostId,
        p.Score,
        p.CreationDate
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1

    union all

    select
        u.Id as UserId,
        u.DisplayName,
        'Answer' as ActivityType,
        p.Id as PostId,
        p.Score,
        p.CreationDate
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 2

    union all

    select
        u.Id as UserId,
        u.DisplayName,
        'Comment' as ActivityType,
        c.Id as PostId,
        c.Score,
        c.CreationDate
    from Users u
    join Comments c on c.UserId = u.Id
),
UserActivityRankings as (
    select
        UserId,
        DisplayName,
        ActivityType,
        PostId,
        Score,
        CreationDate,
        rank() over (partition by UserId, ActivityType order by Score desc, CreationDate desc) as ActivityRank
    from UnionedUserActivity
),
FinalActivitySummary as (
    select
        ua.UserId,
        ua.DisplayName,
        max(case when ua.ActivityType = 'Question' then ua.Score else null end) as MaxQuestionScore,
        max(case when ua.ActivityType = 'Answer' then ua.Score else null end) as MaxAnswerScore,
        max(case when ua.ActivityType = 'Comment' then ua.Score else null end) as MaxCommentScore,
        count(distinct case when ua.ActivityType = 'Question' then ua.PostId else null end) as TotalQuestions,
        count(distinct case when ua.ActivityType = 'Answer' then ua.PostId else null end) as TotalAnswers,
        count(distinct case when ua.ActivityType = 'Comment' then ua.PostId else null end) as TotalComments,
        sum(case when ua.ActivityRank = 1 then 1 else 0 end) as TopRankedActivitiesCount
    from UserActivityRankings ua
    group by ua.UserId, ua.DisplayName
)
select
    qa.QuestionId,
    qa.Title,
    qa.QuestionOwner,
    qa.QuestionOwnerReputation,
    qa.Score as QuestionScore,
    qa.ViewCount,
    qa.AnswerUpVotes,
    qa.AnswerDownVotes,
    qa.RecentComments,
    qa.QuestionOwnerGoldBadges,
    qa.QuestionOwnerSilverBadges,
    qa.QuestionOwnerBronzeBadges,
    qa.DuplicateOfQuestionId,
    qa.CloseReasonName,
    qa.CloseDate,
    qa.UserQuestionRank,
    qa.TagTitleConcat,
    qa.DistinctAnswerersCount,
    fas.MaxQuestionScore as OwnerMaxQuestionScore,
    fas.MaxAnswerScore as OwnerMaxAnswerScore,
    fas.MaxCommentScore as OwnerMaxCommentScore,
    fas.TotalQuestions as OwnerTotalQuestions,
    fas.TotalAnswers as OwnerTotalAnswers,
    fas.TotalComments as OwnerTotalComments,
    fas.TopRankedActivitiesCount as OwnerTopActivities,
    case when qa.CloseDate is not null then 'Closed' else 'Open' end as QuestionStatus
from ComplexQuestionAnalytics qa
left join FinalActivitySummary fas on fas.UserId = qa.QuestionOwnerId
order by qa.QuestionScore desc nulls last
limit 50;