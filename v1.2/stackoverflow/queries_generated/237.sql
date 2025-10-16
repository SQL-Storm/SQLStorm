-- {"query": "237.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1802} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id != r.Id and t.Count < r.Count and t.IsRequired = 0
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostScoreStats as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        sum(case when p.ClosedDate is not null then 1 else 0 end) as ClosedPosts
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId, p.PostTypeId
),
UserActivityRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        coalesce(psq.PostCount,0) as QuestionCount,
        coalesce(psa.PostCount,0) as AnswerCount,
        coalesce(psq.AvgScore,0) as AvgQuestionScore,
        coalesce(psa.AvgScore,0) as AvgAnswerScore,
        row_number() over (order by u.Reputation desc, ub.GoldBadges desc, ub.SilverBadges desc) as UserRank
    from Users u
    left join UserBadgeCounts ub on u.Id = ub.UserId
    left join PostScoreStats psq on u.Id = psq.OwnerUserId and psq.PostTypeId = 1
    left join PostScoreStats psa on u.Id = psa.OwnerUserId and psa.PostTypeId = 2
),
TopQuestionsWithDetails as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.AcceptedAnswerId,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as QuestionRankPerUser
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.ClosedDate is null
),
AcceptedAnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionAnswerSummary as (
    select
        q.QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        q.OwnerName,
        q.CommentCount,
        q.UpVotes,
        q.DownVotes,
        q.AcceptedAnswerId,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerCreationDate,
        a.AnswerOwnerName,
        a.AnswerOwnerReputation,
        q.QuestionRankPerUser
    from TopQuestionsWithDetails q
    left join AcceptedAnswerDetails a on q.AcceptedAnswerId = a.AnswerId
),
UserCloseVoteActivity as (
    select
        ph.UserId,
        count(*) as CloseVotesCast,
        count(distinct ph.PostId) as DistinctPostsClosed,
        max(ph.CreationDate) as LastCloseVoteDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.UserId
),
UserCommentActivity as (
    select
        c.UserId,
        count(*) as TotalComments,
        count(distinct c.PostId) as DistinctPostsCommented,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
UserCombinedActivity as (
    select
        u.Id as UserId,
        coalesce(cc.CloseVotesCast,0) as CloseVotesCast,
        coalesce(cc.DistinctPostsClosed,0) as DistinctPostsClosed,
        coalesce(cm.TotalComments,0) as TotalComments,
        coalesce(cm.DistinctPostsCommented,0) as DistinctPostsCommented
    from Users u
    left join UserCloseVoteActivity cc on u.Id = cc.UserId
    left join UserCommentActivity cm on u.Id = cm.UserId
),
FinalUserStats as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.UserRank,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TotalBadges,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgQuestionScore,
        ua.AvgAnswerScore,
        ca.CloseVotesCast,
        ca.DistinctPostsClosed,
        ca.TotalComments,
        ca.DistinctPostsCommented,
        case
            when ua.Reputation > 10000 and ua.GoldBadges > 5 then 'Expert'
            when ua.Reputation between 1000 and 10000 then 'Intermediate'
            else 'Beginner'
        end as UserLevel
    from UserActivityRank ua
    left join UserCombinedActivity ca on ua.Id = ca.UserId
)
select
    f.Id as UserId,
    f.DisplayName,
    f.UserLevel,
    f.Reputation,
    f.UserRank,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.TotalBadges,
    f.QuestionCount,
    f.AnswerCount,
    f.AvgQuestionScore,
    f.AvgAnswerScore,
    f.CloseVotesCast,
    f.DistinctPostsClosed,
    f.TotalComments,
    f.DistinctPostsCommented,
    qa.QuestionId,
    qa.Title as QuestionTitle,
    qa.QuestionCreationDate,
    qa.QuestionScore,
    qa.ViewCount,
    qa.CommentCount as QuestionCommentCount,
    qa.UpVotes as QuestionUpVotes,
    qa.DownVotes as QuestionDownVotes,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerCreationDate,
    qa.AnswerOwnerName,
    qa.AnswerOwnerReputation,
    rh.Level as TagHierarchyLevel,
    rh.Path as TagHierarchyPath
from FinalUserStats f
left join QuestionAnswerSummary qa on f.Id = qa.OwnerUserId and qa.QuestionRankPerUser = 1
left join RecursiveTagHierarchy rh on qa.Tags is not null and rh.TagName = any(string_to_array(substring(qa.Tags from 2 for length(qa.Tags)-2), '><'))
where f.TotalBadges > 0
order by f.UserRank, qa.QuestionScore desc nulls last
limit 100;