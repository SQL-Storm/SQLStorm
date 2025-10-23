-- {"query": "181.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1860} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(vt_up.VoteCount),0) as TotalUpVotes,
        coalesce(sum(vt_down.VoteCount),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vt_up on vt_up.PostId = p.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vt_down on vt_down.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopTags as (
    select
        t.TagName,
        t.Count,
        p.Id as QuestionPostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
TagActivity as (
    select
        tt.TagName,
        count(distinct tt.QuestionPostId) as QuestionCount,
        sum(tt.Score) as TotalScore,
        avg(tt.ViewCount) as AvgViewCount,
        max(tt.Score) as MaxScore,
        min(tt.Score) as MinScore,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseEvents
    from TopTags tt
    left join Posts p2 on p2.ParentId = tt.QuestionPostId
    left join PostHistory ph on ph.PostId = tt.QuestionPostId
    group by tt.TagName
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(*) filter (where p.PostTypeId = 2) as AnswersPosted,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(p.FavoriteCount) filter (where p.PostTypeId = 1) as TotalFavorites
    from Posts p
    group by p.OwnerUserId
),
UserActivityWithBadges as (
    select
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.CreationDate,
        rua.LastAccessDate,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.CommentCount,
        rua.TotalUpVotes,
        rua.TotalDownVotes,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.DistinctBadges,0) as DistinctBadges,
        coalesce(ups.QuestionsPosted,0) as QuestionsPosted,
        coalesce(ups.AnswersPosted,0) as AnswersPosted,
        coalesce(ups.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(ups.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(ups.MaxQuestionScore,0) as MaxQuestionScore,
        coalesce(ups.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(ups.TotalFavorites,0) as TotalFavorites,
        rua.UserRank
    from RecursiveUserActivity rua
    left join UserBadgeSummary ubs on ubs.UserId = rua.UserId
    left join UserPostStats ups on ups.UserId = rua.UserId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(ph.CreationDate) as LastEditDate,
        max(v.CreationDate) as LastVoteDate,
        greatest(
            coalesce(max(p.CreationDate), timestamp '1970-01-01'),
            coalesce(max(c.CreationDate), timestamp '1970-01-01'),
            coalesce(max(ph.CreationDate), timestamp '1970-01-01'),
            coalesce(max(v.CreationDate), timestamp '1970-01-01')
        ) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.DistinctBadges,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.AvgQuestionScore,
    ua.AvgAnswerScore,
    ua.MaxQuestionScore,
    ua.MaxAnswerScore,
    ua.TotalFavorites,
    ua.UserRank,
    ur.LastActivityDate,
    ta.TagName,
    ta.QuestionCount as TagQuestionCount,
    ta.AnswerCount as TagAnswerCount,
    ta.TotalScore as TagTotalScore,
    ta.AvgViewCount as TagAvgViewCount,
    ta.CloseEvents as TagCloseEvents,
    dl.PostId as DuplicatePostId,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostId as DuplicateRelatedPostId,
    dl.RelatedPostTitle as DuplicateRelatedPostTitle,
    dl.LinkCreationDate as DuplicateLinkDate
from UserActivityWithBadges ua
left join UserRecentActivity ur on ur.UserId = ua.UserId
left join TopTags tt on tt.OwnerUserId = ua.UserId
left join TagActivity ta on ta.TagName = tt.TagName
left join DuplicateLinks dl on dl.PostId = tt.QuestionPostId
where ua.Reputation > 10000
  and (ua.GoldBadges + ua.SilverBadges + ua.BronzeBadges) > 5
  and ta.QuestionCount > 50
  and (ur.LastActivityDate > cast('2024-10-01' as date) - interval '180 days' or ur.LastActivityDate is null)
order by ua.Reputation desc, ua.UserRank asc
limit 100;