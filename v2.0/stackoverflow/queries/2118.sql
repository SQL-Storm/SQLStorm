-- {"query": "2118.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1921}
with recursive UserActivityCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(v.VoteCount), 0) as TotalVotes,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            PostId,
            count(*) as VoteCount
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopActiveUsers as (
    select UserId, DisplayName, Reputation, QuestionCount, AnswerCount, TotalVotes, RepRank
    from UserActivityCounts
    where RepRank <= 100
),
PostTagSplit as (
    select
        p.Id as PostId,
        trim(both from tag) as Tag
    from Posts p,
    lateral (
      select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
    ) s
    where p.Tags is not null and p.PostTypeId = 1
),
UserBadgeCount as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgeSummary as (
    select
        ub.UserId,
        coalesce(sum(case when ub.Class = 1 then ub.BadgeCount end),0) as GoldBadges,
        coalesce(sum(case when ub.Class = 2 then ub.BadgeCount end),0) as SilverBadges,
        coalesce(sum(case when ub.Class = 3 then ub.BadgeCount end),0) as BronzeBadges
    from UserBadgeCount ub
    group by ub.UserId
),
QuestionLinks as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateLinks,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p on p.Id = pl.PostId and p.PostTypeId = 1
    group by pl.PostId
),
UserLatestActivity as (
    select
        u.Id as UserId,
        max(p.LastActivityDate) as LatestPostActivity,
        max(ph.CreationDate) as LatestHistoryActivity,
        max(c.CreationDate) as LatestCommentActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id
),
QuestionsWithCloseInfo as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        cht.Name as CloseReason,
        ph.CreationDate as CloseDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cht on cht.Id = cast(ph.Comment as integer)
    where p.PostTypeId = 1
),
CombinedQuestions as (
    select
        q.QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.CloseReason,
        q.CloseDate,
        coalesce(d.DuplicateLinks,0) as DuplicateLinks,
        coalesce(d.LinkedPosts,0) as LinkedPosts,
        array_agg(distinct pts.Tag) filter (where pts.Tag is not null) as Tags
    from QuestionsWithCloseInfo q
    left join QuestionLinks d on d.PostId = q.QuestionId
    left join PostTagSplit pts on pts.PostId = q.QuestionId
    group by q.QuestionId, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.CloseReason, q.CloseDate, d.DuplicateLinks, d.LinkedPosts
),
RankedAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
),
AnswerAuthorReputation as (
    select ra.AnswerId, ra.QuestionId, ra.Score, ra.CreationDate, ra.AnswerRank, ra.TotalAnswers,
           u.Reputation as AnswererReputation,
           u.DisplayName as AnswererName
    from RankedAnswers ra
    left join Users u on u.Id = ra.OwnerUserId
),
TopAnswersWithAuthors as (
    select *
    from AnswerAuthorReputation
    where AnswerRank <= 3
),
UserEngagement as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserSummary as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        ua.AnswersPosted + ua.QuestionsPosted + ua.CommentsMade as TotalContributions,
        rank() over (order by ua.AnswersPosted + ua.QuestionsPosted + ua.CommentsMade desc) as ContributionRank
    from UserEngagement ua
    left join UserBadgeSummary ub on ub.UserId = ua.UserId
    where ua.AnswersPosted + ua.QuestionsPosted + ua.CommentsMade > 0
)
select
    cu.QuestionId,
    cu.Title,
    cu.Score,
    cu.ViewCount,
    cu.AnswerCount,
    cu.FavoriteCount,
    coalesce(cu.CloseReason, 'Open') as CloseReason,
    cu.CloseDate,
    cu.DuplicateLinks,
    cu.LinkedPosts,
    array_to_string(cu.Tags, ', ') as Tags,
    array_agg(
        ('{"AnswerId":' || coalesce(cast(ta.AnswerId as text), '') ||
         ',"Score":' || coalesce(cast(ta.Score as text), '0') ||
         ',"AnswererReputation":' || coalesce(cast(ta.AnswererReputation as text), '0') ||
         ',"AnswererName":' || '"' || replace(coalesce(ta.AnswererName, ''), '"', '\"') || '"' ||
         ',"AnswerRank":' || coalesce(cast(ta.AnswerRank as text), '0') || '}'
        ) order by ta.AnswerRank
    ) as TopAnswers,
    us.DisplayName as TopContributorName,
    us.TotalContributions,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges
from CombinedQuestions cu
left join TopAnswersWithAuthors ta on ta.QuestionId = cu.QuestionId
left join UserSummary us on us.UserId = (
    select OwnerUserId from Posts where Id = cu.QuestionId and OwnerUserId is not null
    union all
    select OwnerUserId from Posts where ParentId = cu.QuestionId and OwnerUserId is not null
    order by OwnerUserId desc nulls last limit 1
)
group by
    cu.QuestionId, cu.Title, cu.Score, cu.ViewCount, cu.AnswerCount, cu.FavoriteCount, cu.CloseReason, cu.CloseDate, cu.DuplicateLinks, cu.LinkedPosts,
    cu.Tags, us.DisplayName, us.TotalContributions, us.GoldBadges, us.SilverBadges, us.BronzeBadges
having cu.ViewCount > 1000 and (cu.Score > 5 or cu.AnswerCount > 3)
order by cu.ViewCount desc, cu.Score desc
limit 50;