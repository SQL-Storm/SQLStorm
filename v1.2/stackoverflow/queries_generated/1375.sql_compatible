with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName as UserDisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank,
        sum(p.Score) over (partition by u.Id order by p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING and CURRENT ROW) as RunningScoreSum
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
    where
        u.Reputation > 100
),
RecentTopPosts as (
    select
        rua.UserId,
        rua.UserDisplayName,
        rua.PostId,
        rua.PostTypeId,
        rua.Score,
        rua.ViewCount,
        rua.AnswerCount,
        rua.PostCreationDate,
        rua.PostRank,
        rua.RunningScoreSum,
        case 
            when rua.PostTypeId = 1 then 'Question'
            when rua.PostTypeId = 2 then 'Answer'
            when rua.PostTypeId in (4,5) then 'TagWiki'
            else 'Other'
        end as PostCategory,
        substring(region_user.AboutMe from 1 for 45) as AboutMeSnippet
    from
        RecursiveUserActivity rua
        left join Users region_user on rua.UserId = region_user.Id
    where 
        rua.PostRank <= 5
),
TopBadges as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
DuplicateLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, p.Title as PostTitle, rp.Title as RelatedPostTitle
    from PostLinks pl
    inner join Posts p on pl.PostId = p.Id
    inner join Posts rp on pl.RelatedPostId = rp.Id
    where pl.LinkTypeId = 3
),
AnswersWithAcceptedRightJoin as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        acc.Id as AcceptedAnswerId,
        acc.Score as AcceptedAnswerScore,
        a.CreationDate as AnswerDate,
        a.LastActivityDate,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from 
        Posts q
        left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        left join Posts acc on q.AcceptedAnswerId = acc.Id
    where 
        q.PostTypeId = 1
        and q.Score > 5
),
CloseReasonAggregates as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
UserRecentVoteSummary as (
    select 
        v.UserId,
        u.DisplayName as VoteUserDisplayName,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCast,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCast,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoritesCast
    from Votes v
    inner join VoteTypes vt on v.VoteTypeId = vt.Id
    inner join Users u on v.UserId = u.Id
    where v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    group by v.UserId, u.DisplayName
),
QWithoutAnswersOlderThan1Year as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        u.DisplayName as OwnerDisplayName,
        coalesce(awa.AnswerCount, 0) as AnswerCount
    from Posts p
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) awa on awa.ParentId = p.Id
    left join Users u on p.OwnerUserId = u.Id
    where
        p.PostTypeId = 1 
        and p.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
)
select
    rt.UserId,
    rt.UserDisplayName as DisplayName,
    rt.PostId,
    rt.PostCategory,
    rt.Score,
    rt.ViewCount,
    rt.AnswerCount,
    rt.PostCreationDate,
    coalesce(tb.GoldBadges,0) as GoldBadgeCount,
    coalesce(tb.SilverBadges,0) as SilverBadgeCount,
    coalesce(tb.BronzeBadges,0) as BronzeBadgeCount,
    cluster_close.CloseReasonName,
    dlp.PostTitle as DuplicatePostTitle,
    dlp.RelatedPostTitle as DuplicateRelatedTitle,
    awrj.QuestionTitle,
    awrj.AnswerId,
    awrj.IsAccepted,
    awrj.AnswerScore,
    coalesce(urvs.UpVotesCast, 0) as RecentUpVotesByUser,
    coalesce(urvs.DownVotesCast, 0) as RecentDownVotesByUser,
    coalesce(qwa1y.AnswerCount,0) as OldQuestionAnswerCount,
    coalesce(cloer.CloseCount,0) as TotalCloseCounts
from
    RecentTopPosts rt
    left join TopBadges tb on rt.UserId = tb.UserId
    left join CloseReasonAggregates cloer on cloer.CloseReasonId = '101'
    left join DuplicateLinkedPosts dlp on dlp.PostId = rt.PostId
    left join AnswersWithAcceptedRightJoin awrj on awrj.QuestionId = rt.PostId
    left join UserRecentVoteSummary urvs on urvs.UserId = rt.UserId
    left join QWithoutAnswersOlderThan1Year qwa1y on qwa1y.OwnerDisplayName = rt.UserDisplayName and qwa1y.AnswerCount = 0
    left join CloseReasonAggregates cluster_close on cluster_close.CloseReasonId = '102'
where
    (rt.RunningScoreSum > 50 or (coalesce(tb.GoldBadges,0) + coalesce(tb.SilverBadges,0) + coalesce(tb.BronzeBadges,0)) >= 5)
    and (
        rt.PostCategory = 'Question'
        or exists (
            select 1 from Posts p_test where p_test.ParentId = rt.PostId fetch first 1 rows only
        )
    )
union
select
    u.Id as UserId,
    u.DisplayName,
    null as PostId,
    null as PostCategory,
    null as Score,
    null as ViewCount,
    null as AnswerCount,
    null as PostCreationDate,
    0 as GoldBadgeCount,
    0 as SilverBadgeCount,
    0 as BronzeBadgeCount,
    null as CloseReasonName,
    null as DuplicatePostTitle,
    null as DuplicateRelatedTitle,
    null as QuestionTitle,
    0 as AnswerId,
    0 as IsAccepted,
    0 as AnswerScore,
    0 as RecentUpVotesByUser,
    0 as RecentDownVotesByUser,
    0 as OldQuestionAnswerCount,
    0 as TotalCloseCounts
from Users u
where not exists (select 1 from Posts p where p.OwnerUserId = u.Id)
order by UserId, PostCreationDate desc NULLS LAST, Score desc NULLS LAST;