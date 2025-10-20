with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVoteAggregates as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.LastActivityDate,
        p.ClosedDate,
        p.FavoriteCount,
        p.CommentCount,
        p.ContentLicense,
        p.OwnerDisplayName,
        p.LastEditorUserId,
        p.LastEditDate,
        p.LastEditorDisplayName,
        p.ParentId,
        p.CommunityOwnedDate,
        p.Body,
        p.PostTypeId
    from Posts p
    where p.PostTypeId = 1
      and p.Score > 10
      and p.ViewCount > 1000
      and p.ClosedDate is null
),
AnswerRanks as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
AcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreationDate,
        u.DisplayName as AcceptedAnswerOwnerName,
        u.Reputation as AcceptedAnswerOwnerReputation
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
PostCommentsAggregates as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as LinkedPostsCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicatePostsCount
    from PostLinks pl
    group by pl.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionsPosted,
        count(case when p.PostTypeId = 2 then 1 end) as AnswersPosted,
        sum(case when p.PostTypeId in (1,2) then p.Score else 0 end) as TotalPostScore,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc) as LastPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserBadgeRank as (
    select
        b.UserId,
        b.Name,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
),
RecentEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        ph.Comment,
        ph.Text,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRank
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
),
QuestionAnswerSummary as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
DuplicateQuestions as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        q1.Title as DuplicateTitle,
        q2.Title as OriginalTitle
    from PostLinks pl
    join Posts q1 on q1.Id = pl.PostId and q1.PostTypeId = 1
    join Posts q2 on q2.Id = pl.RelatedPostId and q2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
CombinedQuestions as (
    select Id as QuestionId, Title, Tags, Score, ViewCount, AnswerCount, CreationDate, ClosedDate from TopQuestions
    union
    select Id, Title, Tags, Score, ViewCount, AnswerCount, CreationDate, ClosedDate from Posts where PostTypeId = 1 and ClosedDate is not null
)
select
    cq.QuestionId,
    cq.Title,
    cq.Tags,
    cq.Score,
    cq.ViewCount,
    cq.AnswerCount,
    coalesce(a.AnswerScore, 0) as TopAnswerScore,
    coalesce(a.AnswerCreationDate, cq.CreationDate) as TopAnswerDate,
    coalesce(u.DisplayName, 'Unknown') as TopAnswerOwner,
    coalesce(u.Reputation, 0) as TopAnswerOwnerReputation,
    coalesce(pc.CommentCount, 0) as TotalComments,
    coalesce(pls.LinkedPostsCount, 0) as LinkedPosts,
    coalesce(pls.DuplicatePostsCount, 0) as DuplicatePosts,
    coalesce(ub.GoldBadges, 0) as UserGoldBadges,
    coalesce(ub.SilverBadges, 0) as UserSilverBadges,
    coalesce(ub.BronzeBadges, 0) as UserBronzeBadges,
    case when cq.ClosedDate is null then 'Open' else 'Closed' end as QuestionStatus,
    row_number() over (partition by cq.Tags order by cq.Score desc) as RankWithinTag,
    -- aggregate recent commenters per question; use a grouped subquery instead of FILTER + window
    rc.RecentCommenters,
    case
        when cq.ViewCount > 10000 and cq.Score > 50 then 'Hot'
        when cq.ViewCount between 1000 and 10000 and cq.Score between 10 and 50 then 'Warm'
        else 'Cold'
    end as PopularityCategory,
    case
        when coalesce(a.AnswerScore, 0) > cq.Score then 'Answer Outperforms Question'
        else 'Question Leads'
    end as ScoreComparison,
    coalesce(re.EditCount, 0) as RecentEditCount,
    coalesce(re.LastEditDate, cq.CreationDate) as LastEditDate
from CombinedQuestions cq
left join (
    select
        a.ParentId,
        max(a.Score) as AnswerScore,
        max(a.CreationDate) as AnswerCreationDate,
        max(a.Id) as AnswerId
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
) a on a.ParentId = cq.QuestionId
left join Users u on u.Id = (
    select p2.OwnerUserId from Posts p2 where p2.Id = a.AnswerId
)
left join PostCommentsAggregates pc on pc.PostId = cq.QuestionId
left join PostLinkSummary pls on pls.PostId = cq.QuestionId
left join UserBadgeStats ub on ub.UserId = cq.QuestionId
left join (
    select
        ph.PostId,
        count(*) as EditCount,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId
) re on re.PostId = cq.QuestionId
-- collect recent commenters per question in grouped subquery to avoid window+filter referencing wrong aliases
left join (
    select
        c.PostId,
        string_agg(distinct coalesce(uc2.DisplayName, 'Anonymous'), ', ') as RecentCommenters
    from Comments c
    left join Users uc2 on uc2.Id = c.UserId
    group by c.PostId
) rc on rc.PostId = cq.QuestionId
where cq.Score > 20
order by cq.Score desc, cq.ViewCount desc
limit 100;