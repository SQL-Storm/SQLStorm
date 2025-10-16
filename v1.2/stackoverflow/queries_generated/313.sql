-- {"query": "313.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2147} 
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
        count(distinct b.Id) as BadgeCount,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsers as (
    select * from RecursiveUserActivity
    where ReputationRank <= 100
),
PostScoreStats as (
    select
        p.OwnerUserId,
        p.PostTypeId,
        count(*) as PostCount,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        percentile_cont(0.5) within group (order by p.Score) as MedianScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId, p.PostTypeId
),
UserPostDetails as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(psq.PostCount,0) as QuestionCount,
        coalesce(psq.AvgScore,0) as QuestionAvgScore,
        coalesce(psa.PostCount,0) as AnswerCount,
        coalesce(psa.AvgScore,0) as AnswerAvgScore,
        u.CommentCount,
        u.BadgeCount,
        u.ReputationRank,
        -- Calculate activity span in days, handling nulls
        greatest(extract(epoch from (u.LastAccessDate - u.CreationDate))/86400, 1) as ActivityDays,
        -- Calculate average posts per day
        (coalesce(psq.PostCount,0) + coalesce(psa.PostCount,0)) / greatest(extract(epoch from (u.LastAccessDate - u.CreationDate))/86400, 1) as PostsPerDay
    from TopUsers u
    left join PostScoreStats psq on psq.OwnerUserId = u.UserId and psq.PostTypeId = 1
    left join PostScoreStats psa on psa.OwnerUserId = u.UserId and psa.PostTypeId = 2
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Badges b
    group by b.UserId
),
UserActivityWithBadges as (
    select
        upd.*,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TagBasedBadges,0) as TagBasedBadges
    from UserPostDetails upd
    left join UserBadgeSummary ubs on ubs.UserId = upd.UserId
),
PostLinkAnalysis as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.PostTypeId as PostType,
        p2.PostTypeId as RelatedPostType,
        p1.Score as PostScore,
        p2.Score as RelatedPostScore
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),
PostLinkStats as (
    select
        PostType,
        LinkTypeName,
        count(*) as LinkCount,
        avg(PostScore) as AvgPostScore,
        avg(RelatedPostScore) as AvgRelatedPostScore,
        max(PostScore) as MaxPostScore,
        max(RelatedPostScore) as MaxRelatedPostScore
    from PostLinkAnalysis
    group by PostType, LinkTypeName
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > 10
      and q.ViewCount > 1000
),
FilteredTopAnswers as (
    select *
    from TopQuestionsWithAnswers
    where AnswerRank <= 3
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo as (
    select
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.CreationDate,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.CommunityOwnedDate,
        q.ContentLicense,
        q.LastActivityDate,
        q.LastEditDate,
        q.OwnerDisplayName,
        q.LastEditorUserId,
        q.LastEditorDisplayName,
        q.PostTypeId,
        q.ParentId,
        cr.CloseReasonName,
        cr.CloseDate
    from Posts q
    left join QuestionCloseReasons cr on cr.PostId = q.Id
    where q.PostTypeId = 1
),
UserCommentActivity as (
    select
        c.UserId,
        count(*) as TotalComments,
        count(distinct c.PostId) as DistinctPostsCommented,
        max(c.CreationDate) as LastCommentDate,
        min(c.CreationDate) as FirstCommentDate,
        avg(length(c.Text)) as AvgCommentLength
    from Comments c
    group by c.UserId
),
UserVoteSummary as (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesGiven,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesGiven,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoritesGiven,
        sum(case when vt.Name = 'Close' then 1 else 0 end) as CloseVotesGiven
    from Votes v
    inner join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.QuestionAvgScore,
    ua.AnswerCount,
    ua.AnswerAvgScore,
    ua.CommentCount,
    ua.BadgeCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TagBasedBadges,
    ua.ActivityDays,
    ua.PostsPerDay,
    coalesce(uca.TotalComments,0) as TotalComments,
    coalesce(uca.DistinctPostsCommented,0) as DistinctPostsCommented,
    coalesce(uca.AvgCommentLength,0) as AvgCommentLength,
    coalesce(uvs.UpVotesGiven,0) as UpVotesGiven,
    coalesce(uvs.DownVotesGiven,0) as DownVotesGiven,
    coalesce(uvs.FavoritesGiven,0) as FavoritesGiven,
    coalesce(uvs.CloseVotesGiven,0) as CloseVotesGiven,
    pls.LinkTypeName,
    pls.PostType,
    pls.LinkCount,
    pls.AvgPostScore,
    pls.AvgRelatedPostScore,
    pls.MaxPostScore,
    pls.MaxRelatedPostScore,
    fta.QuestionId,
    fta.Title as TopQuestionTitle,
    fta.QuestionScore,
    fta.ViewCount as QuestionViewCount,
    fta.AnswerId,
    fta.AnswerScore,
    fta.AnswerOwnerUserId,
    fta.AnswerOwnerDisplayName,
    qc.CloseReasonName,
    qc.CloseDate
from UserActivityWithBadges ua
left join UserCommentActivity uca on uca.UserId = ua.UserId
left join UserVoteSummary uvs on uvs.UserId = ua.UserId
left join PostLinkStats pls on pls.PostType = 1 and pls.LinkTypeName = 'Duplicate'
left join FilteredTopAnswers fta on fta.AnswerOwnerUserId = ua.UserId
left join QuestionsWithCloseInfo qc on qc.Id = fta.QuestionId
where ua.Reputation > 1000
order by ua.Reputation desc, ua.PostsPerDay desc
limit 100;