with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = false and t2.IsRequired = false
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
        u.LastAccessDate,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByKnownUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
QuestionVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
QuestionCommentsCount as (
    select
        c.PostId,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserTopActivity as (
    select
        UserId,
        DisplayName,
        PostId,
        PostsLast30Days,
        ScoreLast30Days
    from (
        select
            uaw.*,
            row_number() over (partition by UserId order by ScoreLast30Days desc) as rn
        from UserActivityWindow uaw
    ) t
    where rn = 1
)
select
    tq.Id as QuestionId,
    tq.Title,
    tq.OwnerUserId,
    ur.DisplayName as OwnerDisplayName,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    tq.Score as QuestionScore,
    tq.ViewCount,
    coalesce(ans.AnswerCount,0) as AnswerCount,
    coalesce(ans.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(qv.UpVotes,0) as UpVotes,
    coalesce(qv.DownVotes,0) as DownVotes,
    coalesce(qv.Favorites,0) as Favorites,
    coalesce(qc.CommentCount,0) as CommentCount,
    qcr.CloseReasonName,
    qcr.CloseDate,
    ua.PostsLast30Days,
    ua.ScoreLast30Days,
    string_agg(distinct rth.Path, ' | ') as RelatedTagPaths,
    case
        when tq.AcceptedAnswerId is not null then 'Accepted'
        else 'No Accepted Answer'
    end as AcceptedAnswerStatus,
    case
        when ur.Reputation > 10000 and ur.GoldBadges > 5 then 'High Rep Expert'
        when ur.Reputation between 1000 and 10000 then 'Intermediate User'
        else 'New or Low Rep User'
    end as UserCategory
from TopQuestions tq
left join UserReputationStats ur on ur.UserId = tq.OwnerUserId
left join AnswerStats ans on ans.QuestionId = tq.Id
left join QuestionVotes qv on qv.PostId = tq.Id
left join QuestionCommentsCount qc on qc.PostId = tq.Id
left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
left join UserTopActivity ua on ua.UserId = tq.OwnerUserId
left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(tq.Tags, '')) > 0
where (qcr.CloseDate is null or qcr.CloseDate > tq.CreationDate)
group by
    tq.Id, tq.Title, tq.OwnerUserId, ur.DisplayName, ur.Reputation, ur.GoldBadges, ur.SilverBadges, ur.BronzeBadges,
    tq.Score, tq.ViewCount, ans.AnswerCount, ans.AvgAnswerScore, ans.MaxAnswerScore,
    qv.UpVotes, qv.DownVotes, qv.Favorites, qc.CommentCount, qcr.CloseReasonName, qcr.CloseDate,
    ua.PostsLast30Days, ua.ScoreLast30Days, tq.AcceptedAnswerId
order by tq.Score desc, tq.ViewCount desc
limit 100;