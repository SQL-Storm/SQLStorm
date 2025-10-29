with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
LatestUserPosts as (
    select * from RecursiveUserActivity where rn <= 3
),
VotesByUsers as (
    select 
        v.PostId,
        v.VoteTypeId,
        count(*) as VoteCount
    from Votes v
    where v.VoteTypeId in (2,3)
    group by v.PostId, v.VoteTypeId
),
PostWithVotes as (
    select 
        lup.UserId,
        lup.DisplayName,
        lup.Reputation,
        lup.CreationDate,
        lup.LastAccessDate,
        lup.PostId,
        lup.PostTypeId,
        lup.PostScore,
        lup.ViewCount,
        lup.PostCreationDate,
        lup.rn,
        coalesce(uvs_up.VoteCount,0) as UpVotes,
        coalesce(uvs_down.VoteCount,0) as DownVotes,
        coalesce(uvs_up.VoteCount,0) - coalesce(uvs_down.VoteCount,0) as NetVotes
    from LatestUserPosts lup
    left join VotesByUsers uvs_up on uvs_up.PostId = lup.PostId and uvs_up.VoteTypeId = 2
    left join VotesByUsers uvs_down on uvs_down.PostId = lup.PostId and uvs_down.VoteTypeId = 3
),
PostCommentStats as (
    select 
        c.PostId,
        count(distinct c.Id) as TotalComments,
        count(distinct case when c.UserId is null then c.Id end) as AnonymousComments,
        max(c.CreationDate) as LastCommentDate,
        min(c.CreationDate) as FirstCommentDate
    from Comments c
    group by c.PostId
),
PostLinkDuplicates as (
    select 
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionsWithAnswers as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score as QuestionScore,
        p.ViewCount as QuestionViews,
        p.CreationDate as QuestionCreation,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score),0) as TotalAnswerScore,
        count(distinct case when a.OwnerUserId is null then a.Id end) as AnonymousAnswers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate
),
RankingByScore as (
    select 
        qu.QuestionId,
        qu.Title,
        qu.Tags,
        qu.QuestionScore,
        qu.QuestionViews,
        qu.QuestionCreation,
        qu.AnswerCount,
        qu.TotalAnswerScore,
        qu.AnonymousAnswers,
        rank() over (order by qu.QuestionScore desc, qu.AnswerCount desc) as ScoreRank
    from QuestionsWithAnswers qu
),
TagDetails as (
    select 
        t.TagName,
        t.Count as TagUsageCount,
        ex.Body as ExcerptBody,
        w.Body as WikiBody
    from Tags t
    left join Posts ex on ex.Id = t.ExcerptPostId and ex.PostTypeId = 5
    left join Posts w on w.Id = t.WikiPostId and w.PostTypeId = 5
    where t.Count > 10
),
UserBadgeStats as (
    select 
        b.UserId,
        count(*) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserPostScoreAggregates as (
    select 
        p.OwnerUserId as UserId,
        count(*) as TotalPosts,
        sum(p.Score) as SumPostScore,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
FilteredUserStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ups.TotalPosts,0) as TotalPosts,
        coalesce(ups.SumPostScore,0) as SumPostScore,
        coalesce(ups.AvgPostScore,0) as AvgPostScore,
        coalesce(ups.MaxPostScore,0) as MaxPostScore,
        coalesce(ups.MinPostScore,0) as MinPostScore,
        coalesce(ubs.TotalBadges,0) as TotalBadges,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges
    from Users u
    left join UserPostScoreAggregates ups on ups.UserId = u.Id
    left join UserBadgeStats ubs on ubs.UserId = u.Id
    where u.Reputation > 500 and u.CreationDate < (cast('2024-10-01 12:34:56' as timestamp) - interval '1 year')
),
UserRanked as (
    select 
        fus.Id,
        fus.DisplayName,
        fus.Reputation,
        fus.TotalPosts,
        fus.SumPostScore,
        fus.AvgPostScore,
        fus.MaxPostScore,
        fus.MinPostScore,
        fus.TotalBadges,
        fus.GoldBadges,
        fus.SilverBadges,
        fus.BronzeBadges,
        row_number() over (order by fus.SumPostScore desc, fus.TotalBadges desc) as UserRank
    from FilteredUserStats fus
)
select 
    ur.UserRank,
    ur.DisplayName,
    ur.Reputation,
    ur.TotalPosts,
    ur.SumPostScore,
    ur.AvgPostScore,
    ur.MaxPostScore,
    ur.MinPostScore,
    ur.TotalBadges,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    plv.PostId,
    plv.PostTypeId,
    plv.PostScore,
    plv.ViewCount,
    pc.TotalComments,
    pc.AnonymousComments,
    pc.LastCommentDate,
    pc.FirstCommentDate,
    pld.DuplicateCount,
    rb.ScoreRank,
    rb.Title,
    rb.Tags,
    rb.AnswerCount,
    rb.TotalAnswerScore,
    rb.AnonymousAnswers,
    td.TagName,
    td.TagUsageCount,
    substring(td.ExcerptBody from 1 for 100) as TagExcerpt,
    substring(td.WikiBody from 1 for 100) as TagWiki
from UserRanked ur
left join PostWithVotes plv on plv.UserId = ur.Id
left join PostCommentStats pc on pc.PostId = plv.PostId
left join PostLinkDuplicates pld on pld.PostId = plv.PostId
left join RankingByScore rb on rb.QuestionId = plv.PostId and plv.PostTypeId = 1
left join TagDetails td on (',' || replace(replace(rb.Tags, '<', ''), '>', ',') || ',') like '%,' || td.TagName || ',%'
where ur.UserRank <= 50
order by ur.UserRank, plv.PostScore desc, pc.TotalComments desc
limit 200;