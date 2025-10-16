-- {"query": "25.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1846} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and t.IsModeratorOnly = 0 and t.IsRequired = 0
    where not t.TagName = any(r.Path)
    and r.Level < 3
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
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
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
        p.CreationDate,
        p.Score,
        p.ViewCount,
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
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswerCount
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
),
QuestionVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '365 days' preceding and current row) as PostsLastYear
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > current_date - interval '90 days' then 1 else 0 end) as RecentComments
    from Comments c
    group by c.UserId
),
CombinedUserStats as (
    select
        urs.UserId,
        urs.DisplayName,
        urs.Reputation,
        urs.Location,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        ua.PostsLast30Days,
        ua.PostsLastYear,
        coalesce(ucs.CommentCount,0) as CommentCount,
        coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
        coalesce(ucs.RecentComments,0) as RecentComments
    from UserReputationStats urs
    left join UserActivityWindow ua on ua.UserId = urs.UserId
    left join UserCommentStats ucs on ucs.UserId = urs.UserId
    group by urs.UserId, urs.DisplayName, urs.Reputation, urs.Location, urs.GoldBadges, urs.SilverBadges, urs.BronzeBadges, ua.PostsLast30Days, ua.PostsLastYear, ucs.CommentCount, ucs.AvgCommentLength, ucs.RecentComments
)
select
    tq.Id as QuestionId,
    tq.Title,
    tq.OwnerUserId,
    cu.DisplayName as OwnerName,
    tq.CreationDate as QuestionCreationDate,
    tq.Score as QuestionScore,
    tq.ViewCount as QuestionViews,
    coalesce(qv.UpVotes,0) as QuestionUpVotes,
    coalesce(qv.DownVotes,0) as QuestionDownVotes,
    coalesce(qv.FavoriteVotes,0) as QuestionFavorites,
    asn.AnswerCount,
    asn.AvgAnswerScore,
    asn.MaxAnswerScore,
    asn.AnonymousAnswerCount,
    qcr.CloseReason,
    qcr.CloseDate,
    cu.Reputation as OwnerReputation,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    cu.PostsLast30Days,
    cu.PostsLastYear,
    cu.CommentCount,
    cu.AvgCommentLength,
    cu.RecentComments,
    string_agg(distinct rth.TagName, ', ') as RelatedTags,
    case
        when tq.AcceptedAnswerId is not null then 'Accepted'
        else 'No Accepted Answer'
    end as AcceptedAnswerStatus,
    case
        when tq.ViewCount > 10000 then 'Hot'
        when tq.ViewCount between 5000 and 10000 then 'Warm'
        else 'Cold'
    end as PopularityCategory
from TopQuestions tq
left join AnswerStats asn on asn.QuestionId = tq.Id
left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
left join QuestionVotes qv on qv.PostId = tq.Id
left join CombinedUserStats cu on cu.UserId = tq.OwnerUserId
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(substring(tq.Tags from 2 for char_length(tq.Tags)-2), '><'))
where (cu.GoldBadges > 0 or cu.Reputation > 1000)
and (asn.AnswerCount > 2 or asn.AnonymousAnswerCount > 0)
and (qcr.CloseReason is null or qcr.CloseReason not in ('Exact Duplicate', 'Duplicate'))
group by
    tq.Id, tq.Title, tq.OwnerUserId, cu.DisplayName, tq.CreationDate, tq.Score, tq.ViewCount,
    qv.UpVotes, qv.DownVotes, qv.FavoriteVotes,
    asn.AnswerCount, asn.AvgAnswerScore, asn.MaxAnswerScore, asn.AnonymousAnswerCount,
    qcr.CloseReason, qcr.CloseDate,
    cu.Reputation, cu.GoldBadges, cu.SilverBadges, cu.BronzeBadges,
    cu.PostsLast30Days, cu.PostsLastYear, cu.CommentCount, cu.AvgCommentLength, cu.RecentComments,
    tq.AcceptedAnswerId
order by tq.Score desc, tq.ViewCount desc
limit 100;