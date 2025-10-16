-- {"query": "46.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1707} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
PostAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegisteredUsers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
TopQuestionsWithCloseInfo as (
    select
        pas.QuestionId,
        pas.Title,
        pas.OwnerUserId,
        pas.CreationDate,
        pas.QuestionScore,
        pas.ViewCount,
        pas.Tags,
        pas.AnswerCount,
        pas.MaxAnswerScore,
        pas.AvgAnswerScore,
        pas.AnsweredByRegisteredUsers,
        pcr.CloseReasonName,
        pcr.CloseDate,
        ur.DisplayName as OwnerDisplayName,
        ur.Reputation as OwnerReputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges
    from PostAnswerStats pas
    left join PostCloseReasons pcr on pcr.PostId = pas.QuestionId
    left join UserReputationStats ur on ur.UserId = pas.OwnerUserId
    where pas.AnswerCount > 0
),
RankedComments as (
    select
        c.PostId,
        c.Id as CommentId,
        c.UserId,
        c.UserDisplayName,
        c.Score,
        c.CreationDate,
        row_number() over (partition by c.PostId order by c.Score desc, c.CreationDate asc) as CommentRank
    from Comments c
),
TopCommentsPerQuestion as (
    select
        rc.PostId,
        rc.CommentId,
        rc.UserId,
        rc.UserDisplayName,
        rc.Score,
        rc.CreationDate
    from RankedComments rc
    where rc.CommentRank <= 3
),
UserVoteSummary as (
    select
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId, vt.Name
),
UserVotePivot as (
    select
        u.Id as UserId,
        coalesce(sum(case when vt.Name = 'UpMod' then 1 else 0 end), 0) as UpVotes,
        coalesce(sum(case when vt.Name = 'DownMod' then 1 else 0 end), 0) as DownVotes,
        coalesce(sum(case when vt.Name = 'Favorite' then 1 else 0 end), 0) as Favorites,
        coalesce(sum(case when vt.Name = 'Close' then 1 else 0 end), 0) as CloseVotes
    from Users u
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id
),
FinalUserStats as (
    select
        urs.UserId,
        urs.DisplayName,
        urs.Reputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        uvp.UpVotes,
        uvp.DownVotes,
        uvp.Favorites,
        uvp.CloseVotes
    from UserReputationStats urs
    left join UserVotePivot uvp on uvp.UserId = urs.UserId
)
select
    tq.QuestionId,
    tq.Title,
    tq.OwnerDisplayName,
    tq.OwnerReputation,
    tq.GoldBadges,
    tq.SilverBadges,
    tq.BronzeBadges,
    tq.QuestionScore,
    tq.ViewCount,
    coalesce(tq.CloseReasonName, 'Open') as CloseStatus,
    tq.AnswerCount,
    tq.MaxAnswerScore,
    round(tq.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    tq.AnsweredByRegisteredUsers,
    string_agg(distinct rth.TagName, ', ') as RequiredTags,
    tc.CommentId,
    tc.UserDisplayName as Commenter,
    tc.Score as CommentScore,
    tc.CreationDate as CommentDate,
    fus.UpVotes,
    fus.DownVotes,
    fus.Favorites,
    fus.CloseVotes
from TopQuestionsWithCloseInfo tq
left join RecursiveTagHierarchy rth on position('<' || rth.TagName || '>' in tq.Tags) > 0
left join TopCommentsPerQuestion tc on tc.PostId = tq.QuestionId
left join FinalUserStats fus on fus.DisplayName = tq.OwnerDisplayName
group by
    tq.QuestionId,
    tq.Title,
    tq.OwnerDisplayName,
    tq.OwnerReputation,
    tq.GoldBadges,
    tq.SilverBadges,
    tq.BronzeBadges,
    tq.QuestionScore,
    tq.ViewCount,
    tq.CloseReasonName,
    tq.AnswerCount,
    tq.MaxAnswerScore,
    tq.AvgAnswerScore,
    tq.AnsweredByRegisteredUsers,
    tc.CommentId,
    tc.UserDisplayName,
    tc.Score,
    tc.CreationDate,
    fus.UpVotes,
    fus.DownVotes,
    fus.Favorites,
    fus.CloseVotes
order by tq.QuestionScore desc, tq.ViewCount desc, tc.Score desc
limit 100;