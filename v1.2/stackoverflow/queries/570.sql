with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
LatestUserPosts as (
    select UserId, DisplayName, Reputation, PostId, PostTypeId, Score, ViewCount, PostCreationDate
    from RecursiveUserActivity
    where rn <= 5
),
PostVoteStats as (
    select 
        v.PostId,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
        count(case when vt.Name = 'Favorite' then 1 end) as Favorites
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        coalesce(ans.AnswerCount, 0) as AnswerCount,
        coalesce(ans.AverageAnswerScore, 0) as AvgAnswerScore,
        q.ViewCount,
        q.CreationDate as QuestionCreationDate,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation
    from Posts q
    left join (
        select 
            ParentId,
            count(*) as AnswerCount,
            avg(Score) as AverageAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on q.Id = ans.ParentId
    join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
),
TagUsage as (
    select 
        t.TagName,
        count(distinct p.Id) as QuestionCount,
        sum(p.Score) as TotalScore,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViewCount
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
    group by t.TagName
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserActivitySummary as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join UserBadgeCounts ub on ub.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
TopQuestionsWithAnswersAndVotes as (
    select 
        q.QuestionId,
        q.Title,
        q.OwnerDisplayName,
        q.OwnerReputation,
        q.QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.AvgAnswerScore,
        pvs.UpVotes,
        pvs.DownVotes,
        pvs.Favorites,
        q.QuestionCreationDate,
        qrt.CloseReasonName,
        row_number() over (partition by q.OwnerUserId order by q.QuestionScore desc) as rn
    from QuestionAnswerStats q
    left join PostVoteStats pvs on q.QuestionId = pvs.PostId
    left join QuestionCloseReasons qrt on q.QuestionId = qrt.PostId
    where q.AnswerCount > 0
)
select 
    t.QuestionId,
    t.Title,
    t.OwnerDisplayName,
    t.OwnerReputation,
    t.QuestionScore,
    t.ViewCount,
    t.AnswerCount,
    t.AvgAnswerScore,
    t.UpVotes,
    t.DownVotes,
    t.Favorites,
    t.CloseReasonName,
    t.QuestionCreationDate,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.TotalPosts,
    uas.TotalComments,
    coalesce(u.LastAccessDate, timestamp '1970-01-01') as LastAccessDate,
    case 
        when t.CloseReasonName is null then 'Open'
        else 'Closed: ' || t.CloseReasonName
    end as PostStatus,
    concat_ws(' | ',
        t.Title,
        coalesce(nullif(u.Location, ''), 'Unknown Location'),
        'Reputation: ' || t.OwnerReputation,
        'Badges: G' || uas.GoldBadges || '/S' || uas.SilverBadges || '/B' || uas.BronzeBadges,
        'Answers: ' || t.AnswerCount,
        'Views: ' || t.ViewCount,
        'Status: ' || case when t.CloseReasonName is null then 'Open' else 'Closed' end
    ) as SummaryString
from TopQuestionsWithAnswersAndVotes t
join Users u on u.DisplayName = t.OwnerDisplayName
left join UserActivitySummary uas on uas.Id = u.Id
where t.rn <= 3

union

select 
    t.QuestionId,
    t.Title,
    t.OwnerDisplayName,
    t.OwnerReputation,
    t.QuestionScore,
    t.ViewCount,
    t.AnswerCount,
    t.AvgAnswerScore,
    pvs.UpVotes,
    pvs.DownVotes,
    pvs.Favorites,
    t.CloseReasonName,
    t.QuestionCreationDate,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as TotalPosts,
    0 as TotalComments,
    timestamp '1970-01-01' as LastAccessDate,
    'Open' as PostStatus,
    concat_ws(' | ',
        t.Title,
        'Unknown Location',
        'Reputation: ' || t.OwnerReputation,
        'Badges: G0/S0/B0',
        'Answers: ' || t.AnswerCount,
        'Views: ' || t.ViewCount,
        'Status: Open'
    ) as SummaryString
from TopQuestionsWithAnswersAndVotes t
left join PostVoteStats pvs on t.QuestionId = pvs.PostId
where t.OwnerDisplayName is null

order by QuestionScore desc, ViewCount desc
limit 50;