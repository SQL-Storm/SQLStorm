-- {"query": "424.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1841} 
with RecursiveUserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.Class
),
UserBadgeRanks as (
    select
        UserId,
        DisplayName,
        Reputation,
        CreationDate,
        Class,
        BadgeCount,
        row_number() over (partition by UserId order by Class) as BadgeClassRank
    from RecursiveUserBadgeCounts
),
TopBadgesPerUser as (
    select
        UserId,
        DisplayName,
        Reputation,
        CreationDate,
        Class,
        BadgeCount
    from UserBadgeRanks
    where BadgeClassRank = 1
),
QuestionAnswerStats as (
    select
        p.OwnerUserId as UserId,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        avg(case when p.PostTypeId = 1 then p.Score end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score end) as AvgAnswerScore,
        max(p.CreationDate) as LastPostDate
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(qas.QuestionCount,0) as QuestionCount,
        coalesce(qas.AnswerCount,0) as AnswerCount,
        coalesce(qas.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(qas.AvgAnswerScore,0) as AvgAnswerScore,
        qas.LastPostDate,
        coalesce(tbp.Class, 0) as TopBadgeClass,
        coalesce(tbp.BadgeCount, 0) as TopBadgeCount
    from Users u
    left join QuestionAnswerStats qas on u.Id = qas.UserId
    left join TopBadgesPerUser tbp on u.Id = tbp.UserId
),
UserCommentCounts as (
    select
        c.UserId,
        count(*) as CommentCount,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveCommentCount
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserVoteStats as (
    select
        v.UserId,
        count(*) as VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesGiven,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesGiven
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
UserSummary as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgQuestionScore,
        ua.AvgAnswerScore,
        ua.LastPostDate,
        ua.TopBadgeClass,
        ua.TopBadgeCount,
        coalesce(uc.CommentCount, 0) as CommentCount,
        coalesce(uc.PositiveCommentCount, 0) as PositiveCommentCount,
        coalesce(uv.VoteCount, 0) as VoteCount,
        coalesce(uv.UpVotesGiven, 0) as UpVotesGiven,
        coalesce(uv.DownVotesGiven, 0) as DownVotesGiven,
        -- Calculate activity span in days
        case 
            when ua.LastPostDate is not null then 
                extract(epoch from (ua.LastPostDate - ua.CreationDate)) / 86400.0
            else
                null
        end as ActivitySpanDays
    from UserActivity ua
    left join UserCommentCounts uc on ua.UserId = uc.UserId
    left join UserVoteStats uv on ua.UserId = uv.UserId
),
RankedUsers as (
    select
        *,
        rank() over (order by Reputation desc, QuestionCount desc, AnswerCount desc) as ReputationRank,
        dense_rank() over (order by TopBadgeClass desc, TopBadgeCount desc) as BadgeRank,
        ntile(10) over (order by ActivitySpanDays desc nulls last) as ActivityDecile
    from UserSummary
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        -- Extract first tag from Tags string (assuming format: <tag1><tag2><tag3>)
        substring(p.Tags from '<([^>]+)>') as FirstTag,
        -- Count number of tags by counting occurrences of '<' in Tags string
        (length(p.Tags) - length(replace(p.Tags, '<', ''))) as TagCount
    from Posts p
    where p.PostTypeId in (1,2)
),
PostWithUserInfo as (
    select
        fp.*,
        ru.DisplayName as OwnerDisplayName,
        ru.Reputation as OwnerReputation,
        ru.ReputationRank,
        ru.BadgeRank,
        ru.ActivityDecile
    from FilteredPosts fp
    left join RankedUsers ru on fp.OwnerUserId = ru.UserId
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as RelatedPostsCount,
        sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinksCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
FinalPostStats as (
    select
        pwi.*,
        pls.RelatedPostsCount,
        pls.DuplicateLinksCount,
        pls.LastLinkDate,
        -- Window function: rank posts by score partitioned by OwnerUserId
        rank() over (partition by pwi.OwnerUserId order by pwi.Score desc) as PostScoreRank,
        -- Correlated subquery: count comments with positive score on this post
        (select count(*) from Comments c where c.PostId = pwi.Id and c.Score > 0) as PositiveCommentsCount,
        -- Complex predicate: check if post is highly active and popular
        case 
            when pwi.Score > 10 and pwi.ViewCount > 1000 and pwi.AnswerCount > 3 then 1
            else 0
        end as IsPopularQuestion,
        -- String expression: concatenate title with first tag and owner's display name
        concat_ws(' | ', coalesce(pwi.Title, '[No Title]'), coalesce(pwi.FirstTag, '[No Tag]'), coalesce(pwi.OwnerDisplayName, '[No Owner]')) as PostSummary
    from PostWithUserInfo pwi
    left join PostLinkSummary pls on pwi.Id = pls.PostId
)
select
    fps.Id as PostId,
    fps.PostTypeId,
    fps.PostSummary,
    fps.Score,
    fps.ViewCount,
    fps.AnswerCount,
    fps.CommentCount,
    fps.FavoriteCount,
    fps.ClosedDate,
    fps.LastActivityDate,
    fps.OwnerUserId,
    fps.OwnerDisplayName,
    fps.OwnerReputation,
    fps.ReputationRank,
    fps.BadgeRank,
    fps.ActivityDecile,
    fps.RelatedPostsCount,
    fps.DuplicateLinksCount,
    fps.LastLinkDate,
    fps.PostScoreRank,
    fps.PositiveCommentsCount,
    fps.IsPopularQuestion,
    -- Complex calculation: weighted score combining votes, views, and badge rank
    (fps.Score * 2) + (fps.ViewCount / 100) + (fps.BadgeRank * 5) as WeightedPopularityScore
from FinalPostStats fps
where fps.IsPopularQuestion = 1
order by WeightedPopularityScore desc, fps.Score desc
limit 100;