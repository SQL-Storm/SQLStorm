with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(coalesce(vu.UpVotes,0)) as TotalUpVotes,
        sum(coalesce(vd.DownVotes,0)) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.CreationDate) as RankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select PostId, count(*) as UpVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'UpMod'
        group by PostId
    ) vu on vu.PostId = p.Id
    left join (
        select PostId, count(*) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'DownMod'
        group by PostId
    ) vd on vd.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
), LatestCloseReasons as (
    select ph.PostId, crt.Name as CloseReason, ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
), PostWithLatestCloseReason as (
    select p.Id as PostId, p.Title, p.CreationDate, p.Score, p.ViewCount,
           p.Tags,
           lcr.CloseReason,
           coalesce(pl.LinkCount, 0) as LinkCount,
           coalesce(ans.AnswerCount, 0) as AnswersCount
    from Posts p
    left join (select PostId, count(*) as LinkCount from PostLinks group by PostId) pl on pl.PostId = p.Id
    left join LatestCloseReasons lcr on lcr.PostId = p.Id and lcr.rn = 1
    left join (select ParentId, count(*) as AnswerCount from Posts where PostTypeId = 2 group by ParentId) ans on ans.ParentId = p.Id
    where p.PostTypeId = 1
), TagExplode as (
    select
        pwr.PostId,
        unnest(string_to_array(substring(pwr.Tags from 2 for length(pwr.Tags) - 2), '><')) as Tag
    from PostWithLatestCloseReason pwr
), UserBadges as (
    select u.Id as UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
), TagPopularity as (
    select
        t.TagName,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        max(p.Score) as MaxScore,
        avg(p.Score) as AvgScore
    from Tags t
    left join Posts p on p.Tags like '%' || t.TagName || '%'
    group by t.TagName
), TopUsersAndTags as (
    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.QuestionCount,
        r.AnswerCount,
        r.CommentCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        tp.TagName,
        tp.QuestionCount as TagQuestionCount,
        tp.MaxScore as TagMaxScore,
        tp.AvgScore as TagAvgScore,
        row_number() over (partition by r.UserId order by tp.QuestionCount desc nulls last) as TagRank
    from RecursiveUserActivity r
    left join UserBadges ub on ub.UserId = r.UserId
    cross join TagPopularity tp
    left join TagExplode te on te.Tag = tp.TagName
        and te.PostId in (
            select p2.Id from Posts p2 where p2.OwnerUserId = r.UserId and p2.PostTypeId = 1
        )
    where tp.TagName = te.Tag OR te.Tag IS NULL
), UserPostActivity as (
    select p.Id, p.CreationDate, p.PostTypeId, p.Score,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore,
        p.OwnerUserId
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
), ScoreImprovement as (
    select
        OwnerUserId,
        count(*) filter (where (NextScore is not null and NextScore > Score)) as ImprovedPostsCount,
        count(*) filter (where (PrevScore is not null and PrevScore > Score)) as DeclinedPostsCount
    from UserPostActivity
    group by OwnerUserId
)
select
    t.PostId,
    t.Title,
    t.CreationDate as QuestionCreated,
    t.Score as QuestionScore,
    t.ViewCount,
    t.CloseReason,
    t.LinkCount,
    t.AnswersCount,
    string_agg(distinct te.Tag, ', ') as Tags,
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.QuestionCount,
    r.AnswerCount,
    r.CommentCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    si.ImprovedPostsCount,
    si.DeclinedPostsCount
from PostWithLatestCloseReason t
join Posts p on p.Id = t.PostId and p.OwnerUserId is not null
join RecursiveUserActivity r on r.UserId = p.OwnerUserId
join UserBadges ub on ub.UserId = r.UserId
left join UserPostActivity upa on upa.OwnerUserId = r.UserId
left join ScoreImprovement si on si.OwnerUserId = r.UserId
left join TagExplode te on te.PostId = t.PostId
where t.Score > coalesce((
    select avg(Score) * 1.25
    from Posts
    where PostTypeId = 1
    and CreationDate >= cast('2024-10-01' as date) - interval '1 year'
), 0)
group by t.PostId, t.Title, t.CreationDate, t.Score, t.ViewCount, t.CloseReason, t.LinkCount, t.AnswersCount,
         r.UserId, r.DisplayName, r.Reputation, r.QuestionCount, r.AnswerCount, r.CommentCount, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
         si.ImprovedPostsCount, si.DeclinedPostsCount
order by t.Score desc, r.Reputation desc
limit 100;